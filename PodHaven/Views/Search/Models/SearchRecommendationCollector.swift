// Copyright Justin Bishop, 2026

import CoreMedia
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Tagged

// MARK: - SearchRecommendationCollector

// Owned by SearchViewModel for the lifetime of the Search tab. Owns RSS
// fetch + embed + score work for two surfaces:
//
//   - Top-category trending: chip switches reuse a long-lived shared podcast
//     cache so a podcast that appears in multiple chips is downloaded and
//     scored once.
//   - Typed search: each debounced query builds a per-query overlay that
//     reuses already-scored shared podcasts and discards query-only misses
//     when the query changes.
//
// Trending work isn't cancelled when the active chip switches. Typed-search
// overlay work is cancelled when the query changes.
@Observable @MainActor
final class SearchRecommendationCollector {
  nonisolated private static let log = Log.as(LogSubsystem.SearchView.recommendations)

  // MARK: - Tunable Caps

  // First P podcasts from each source ranking are eligible.
  nonisolated static let podcastCap = 25

  // Newest E episodes per podcast feed enter the candidate gate / embedding
  // pipeline.
  nonisolated static let episodesPerPodcast = 10

  // Discovery removes freshness, so neutral content clusters around the
  // remapped 0.5 baseline.
  nonisolated static let scoreFloor: Float = 0.5

  // RSS fan-out concurrency. Embedding still serializes through the
  // ContextualEmbedding actor; wider RSS concurrency only buys faster
  // first-paint.
  nonisolated static let rssConcurrency = 8

  // Wait for the active source's ranking to remain stable for this long
  // before kicking the per-podcast pipeline. Sits between the iTunes
  // result emit and RSS fan-out; independent of the existing 400 ms
  // search-query debounce.
  nonisolated static let stableSourceDebounce: Duration = .seconds(1)

  // MARK: - Source

  enum Source: Sendable, Hashable {
    case search(query: String)
    case trending(genreID: Int?, title: String)

    var discoveryListTitle: String {
      switch self {
      case .search(let query): return query
      case .trending(let genreID, let title): return genreID == nil ? "Top picks" : title
      }
    }
  }

  // MARK: - Banner State

  enum BannerState: Equatable, Sendable {
    case hidden
    case loading
    case loaded(count: Int)
  }

  // MARK: - Scored Episode

  struct ScoredEpisode: Identifiable, Sendable, Hashable {
    var id: MediaGUID { episode.mediaGUID }
    let episode: UnsavedPodcastEpisode
    let score: Float
    // The cache key of the entry this pick came from. UnsavedPodcastEpisode's
    // feedURL is parsed from the RSS (atom:link self / itunes:new-feed-url)
    // and can differ from the URL we downloaded, so removePick can't use
    // `episode.feedURL` to find the owning entry.
    let entryFeedURL: FeedURL
  }

  // MARK: - Dependencies

  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.taskPriority) private var taskPriority

  @ObservationIgnored private let downloadManager: DownloadManager

  // MARK: - Observed Outputs

  // Whichever surface SearchView is currently rendering. Set by
  // SearchViewModel; changes the banner / discovery list reads only.
  var activeSource: Source? = nil

  // MARK: - Internal State

  // Entries referenced by any loaded trending chip's ranking. An entry
  // here survives chip switches and search-query changes for the
  // SearchViewModel's lifetime.
  private var permanent: [FeedURL: CachedPodcastEntry] = [:]

  // Entries referenced only by the current typed-search ranking. Purged
  // (with their in-flight `DownloadTask`s cancelled) whenever the active
  // query changes.
  private var temporary: [FeedURL: CachedPodcastEntry] = [:]

  // Per top-category source: the ordered feed URLs selected from that
  // category's current iTunes result snapshot.
  private var trendingSourceIndex: [Source: [FeedURL]] = [:]

  // Current typed-search ranking; replaced on every recordSourcePodcasts
  // call. Purging `temporary` is gated on the embedded `query` changing.
  private var typedSearchOverlay: TypedSearchOverlay? = nil

  // Per-source stable-source debouncer. Restarted whenever a new ranking
  // lands for that source.
  private var debouncers: [Source: Debounce] = [:]

  // One stored task drains pending feed URLs.
  private var drainTask: Task<Void, Never>?

  // FIFO of feed URLs ready to be picked up by the drain task.
  private var pendingDrainQueue: [FeedURL] = []
  private var drainContinuation: CheckedContinuation<Void, Never>?

  // Feed URLs whose pipeline is mid-flight.
  private var inFlight: Set<FeedURL> = []

  // Set once the engine has emitted a scoringRevision tick after start without
  // producing a context (e.g., user has too few signals). Surfaces .hidden on
  // the banner and lets the drain proceed instead of blocking forever.
  private var scoringUnavailable = false

  // Watches the engine after we surface unavailable, so we can re-queue
  // already-finished entries when scoring later warms.
  private var scoringContextWatcherTask: Task<Void, Never>?

  // MARK: - Lifecycle

  init() {
    downloadManager = DownloadManager(session: Container.shared.podcastFeedSession())
  }

  // MARK: - Public API

  // Update which source the banner / discovery list reads from. Does not
  // trigger pipeline work; pair with `recordSourcePodcasts` for that.
  func setActiveSource(_ source: Source?) {
    Self.log.debug("Active source -> \(String(describing: source))")
    guard source != activeSource else { return }
    activeSource = source
  }

  // Called by SearchViewModel after iTunes search / trending returns. The
  // collector reconciles `podcasts` against the DB, drops subscribed ones,
  // takes the first `podcastCap` survivors as the source's ranking, and
  // queues the missing podcasts for RSS+embed+score work after the
  // `stableSourceDebounce`. Typed-search recordings replace the prior
  // overlay if `source.query` differs.
  func recordSourcePodcasts(
    source: Source,
    podcasts: [PodcastWithEpisodeMetadata<ListedPodcast>]
  ) {
    Self.log.debug(
      "Recording source \(String(describing: source)) with \(podcasts.count) podcasts"
    )

    let debouncer = debouncers[source] ?? Debounce(duration: Self.stableSourceDebounce)
    debouncers[source] = debouncer

    let capped = Array(podcasts.prefix(Self.podcastCap))
    debouncer { [weak self] in
      guard let self else { return }
      await self.reconcileAndIngest(source: source, podcasts: capped)
    }
  }

  // Cancel the drain task, cancel every entry's in-flight download, and
  // empty all in-memory caches. Called when the Search tab is left so
  // arbitrary discovery candidates don't live in memory forever.
  func tearDown() {
    Self.log.debug("Tearing down collector")
    drainTask?.cancel()
    if let continuation = drainContinuation {
      drainContinuation = nil
      continuation.resume()
    }
    drainTask = nil
    scoringContextWatcherTask?.cancel()
    scoringContextWatcherTask = nil
    scoringUnavailable = false

    let toCancel = Array(permanent.values) + Array(temporary.values)
    permanent.removeAll()
    temporary.removeAll()
    trendingSourceIndex.removeAll()
    typedSearchOverlay = nil
    // Dropping the Debounce references doesn't cancel their pending sleep
    // tasks — those keep running until the sleep deadline passes and then
    // re-enter the (now stale) action. Cancel each task explicitly so any
    // post-teardown wake-up bails before repopulating caches.
    for debouncer in debouncers.values { debouncer.cancel() }
    debouncers.removeAll()
    pendingDrainQueue.removeAll()
    inFlight.removeAll()
    activeSource = nil

    // `drainTask?.cancel()` above propagates through structured concurrency,
    // which causes each `processFeedURL` child to resume via `AsyncLatch`'s
    // onCancel and clear `entry.fetchToken` before this Task body could run
    // `entry.cancel()`. Go through the manager so the active downloads are
    // cancelled even after the entries have lost their fetch tokens.
    Task { [downloadManager] in
      await downloadManager.cancelAllDownloads()
      for entry in toCancel { await entry.cancel() }
    }
  }

  // The discovery list calls this after a successful row action that
  // materialized or mutated the episode. We drop the pick from its
  // owning entry's scored episodes; the row's episode detail handles
  // the unsaved→saved transition on its own.
  //
  // `feedURL` is the caller's view of the feed (from `ListedEpisode.feedURL`),
  // which mirrors the RSS-parsed `atom:link self` / `itunes:new-feed-url` and
  // can differ from the cache key. Try the direct lookup first; if it misses,
  // scan by mediaGUID and use the pick's recorded `entryFeedURL`.
  func removePick(feedURL: FeedURL, mediaGUID: MediaGUID) {
    Self.log.debug("Removing pick \(mediaGUID)")
    if let entry = permanent[feedURL] ?? temporary[feedURL],
      entry.scoredEpisodes.contains(where: { $0.id == mediaGUID })
    {
      entry.scoredEpisodes.removeAll { $0.id == mediaGUID }
      return
    }
    for entry in permanent.values
    where entry.scoredEpisodes.contains(where: { $0.id == mediaGUID }) {
      entry.scoredEpisodes.removeAll { $0.id == mediaGUID }
      return
    }
    for entry in temporary.values
    where entry.scoredEpisodes.contains(where: { $0.id == mediaGUID }) {
      entry.scoredEpisodes.removeAll { $0.id == mediaGUID }
      return
    }
  }

  // MARK: - Reconcile & Ingest

  private func reconcileAndIngest(
    source: Source,
    podcasts: [PodcastWithEpisodeMetadata<ListedPodcast>]
  ) async {
    let feedURLs = podcasts.map(\.podcast.slotID)
    let iTunesIDs = podcasts.compactMap(\.podcast.iTunesID)
    let savedSnapshot = await firstObservationEmission(
      feedURLs: feedURLs,
      iTunesIDs: iTunesIDs
    )

    var savedByFeedURL: [FeedURL: PodcastWithEpisodeMetadata<ListablePodcast>] = [:]
    var savedByITunesID: [ITunesPodcastID: PodcastWithEpisodeMetadata<ListablePodcast>] = [:]
    for entry in savedSnapshot {
      savedByFeedURL[entry.podcast.feedURL] = entry
      if let iTunesID = entry.podcast.iTunesID {
        savedByITunesID[iTunesID] = entry
      }
    }

    var reconciledFeedURLs = [FeedURL](capacity: podcasts.count)
    var reconciledPodcastIDs: [FeedURL: Podcast.ID] = [:]
    var droppedSubscribed = 0
    for entry in podcasts {
      let slotURL = entry.podcast.slotID
      let bridged: PodcastWithEpisodeMetadata<ListablePodcast>?
      if let direct = savedByFeedURL[slotURL] {
        bridged = direct
      } else if let iTunesID = entry.podcast.iTunesID,
        let byITunes = savedByITunesID[iTunesID]
      {
        bridged = byITunes
      } else {
        bridged = nil
      }

      if let bridged, bridged.podcast.subscribed {
        droppedSubscribed += 1
        continue
      }

      // Prefer the canonical feed URL from the DB row when the iTunes
      // search result bridges to a saved-but-unsubscribed podcast — that's
      // the key the shared cache uses to dedup across categories.
      let canonicalFeedURL = bridged?.podcast.feedURL ?? slotURL
      reconciledFeedURLs.append(canonicalFeedURL)
      if let bridged { reconciledPodcastIDs[canonicalFeedURL] = bridged.podcast.id }
    }

    Self.log.debug(
      """
      Reconciled \(String(describing: source)): \
      \(reconciledFeedURLs.count) survived (\(droppedSubscribed) subscribed)
      """
    )

    applyReconciledRanking(
      source: source,
      feedURLs: reconciledFeedURLs,
      podcastIDs: reconciledPodcastIDs
    )
  }

  private func applyReconciledRanking(
    source: Source,
    feedURLs: [FeedURL],
    podcastIDs: [FeedURL: Podcast.ID]
  ) {
    switch source {
    case .trending:
      trendingSourceIndex[source] = feedURLs
      for feedURL in feedURLs {
        if let promoted = temporary.removeValue(forKey: feedURL) {
          permanent[feedURL] = promoted
        } else if permanent[feedURL] == nil {
          permanent[feedURL] = CachedPodcastEntry(
            feedURL: feedURL,
            podcastID: podcastIDs[feedURL]
          )
        }
        scheduleDrain(for: feedURL)
      }

    case .search(let query):
      let previousQuery = typedSearchOverlay?.query
      typedSearchOverlay = TypedSearchOverlay(query: query, feedURLs: feedURLs)
      if previousQuery != query {
        // Keep temporary entries whose feedURL re-appears under the new
        // query: their in-flight RSS / embed work carries forward instead
        // of being orphaned by the inFlight guard in `scheduleDrain`.
        pruneTemporary(keeping: Set(feedURLs))
        if let previousQuery {
          debouncers.removeValue(forKey: .search(query: previousQuery))
        }
      }
      for feedURL in feedURLs {
        if permanent[feedURL] == nil, temporary[feedURL] == nil {
          temporary[feedURL] = CachedPodcastEntry(
            feedURL: feedURL,
            podcastID: podcastIDs[feedURL]
          )
        }
        scheduleDrain(for: feedURL)
      }
    }

    ensureDrainTaskRunning()
  }

  // Cancel and drop temporary entries whose feedURL is NOT in `survivors`,
  // and strip their feed URLs from the pending drain queue. Survivors stay
  // so already-in-flight work carries across a typed-search query change.
  private func pruneTemporary(keeping survivors: Set<FeedURL>) {
    guard !temporary.isEmpty else { return }
    var toCancel: [CachedPodcastEntry] = []
    var purgedURLs: Set<FeedURL> = []
    for (url, entry) in temporary where !survivors.contains(url) {
      toCancel.append(entry)
      purgedURLs.insert(url)
    }
    guard !purgedURLs.isEmpty else { return }
    for url in purgedURLs { temporary.removeValue(forKey: url) }
    pendingDrainQueue.removeAll { purgedURLs.contains($0) }
    Task {
      for entry in toCancel { await entry.cancel() }
    }
  }

  private func scheduleDrain(for feedURL: FeedURL) {
    guard !inFlight.contains(feedURL) else { return }
    let status = entry(for: feedURL)?.status
    guard status != .scored else { return }
    if pendingDrainQueue.contains(feedURL) { return }
    pendingDrainQueue.append(feedURL)
    drainContinuation?.resume()
    drainContinuation = nil
  }

  private func entry(for feedURL: FeedURL) -> CachedPodcastEntry? {
    if let entry = permanent[feedURL] { return entry }
    return temporary[feedURL]
  }

  private func awaitScoringContext() async {
    if recommendationEngine.hasScoringContext {
      scoringUnavailable = false
      return
    }
    recommendationEngine.start()
    // AppLauncher pre-starts the engine, so a no-context revision can already be in the past; don't subscribe to a stream whose only emit would be the bootstrap replay.
    if recommendationEngine.scoringRevision > 0 {
      scoringUnavailable = true
      startScoringContextWatcherIfNeeded()
      return
    }
    for await revision in recommendationEngine.$scoringRevision.stream() {
      if Task.isCancelled { return }
      if recommendationEngine.hasScoringContext {
        scoringUnavailable = false
        return
      }
      if revision == 0 { continue }
      scoringUnavailable = true
      startScoringContextWatcherIfNeeded()
      return
    }
  }

  private func startScoringContextWatcherIfNeeded() {
    if let task = scoringContextWatcherTask, !task.isCancelled { return }
    scoringContextWatcherTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      await self.observeScoringContextWarmth()
    }
  }

  private func observeScoringContextWarmth() async {
    // Engine state can change between the caller setting scoringUnavailable
    // and this watcher subscribing. Check on every emit including bootstrap
    // (don't dropFirst) so a fast-warming engine doesn't slip past us.
    for await _ in recommendationEngine.$scoringRevision.stream() {
      if Task.isCancelled { return }
      if recommendationEngine.hasScoringContext {
        handleScoringContextBecameAvailable()
        return
      }
    }
  }

  private func handleScoringContextBecameAvailable() {
    scoringUnavailable = false
    scoringContextWatcherTask = nil
    let allEntries = Array(permanent.values) + Array(temporary.values)
    for entry in allEntries where entry.status == .scored && entry.scoredEpisodes.isEmpty {
      entry.status = .pending
      scheduleDrain(for: entry.feedURL)
    }
    ensureDrainTaskRunning()
  }

  // MARK: - Drain Task

  private func ensureDrainTaskRunning() {
    if let drainTask, !drainTask.isCancelled { return }
    drainTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      await self.runDrainLoop()
    }
  }

  private func runDrainLoop() async {
    // Without a hydrated scoring cache, `similarityScore(forEmbedding:)`
    // returns nil for every candidate, all picks silently filter out, and
    // each entry would be marked `.scored` with no episodes — permanent
    // until the collector is torn down. Block until the engine is ready.
    await awaitScoringContext()
    if Task.isCancelled { return }

    await withTaskGroup(of: Void.self) { group in
      var activeChildren = 0
      while !Task.isCancelled {
        while activeChildren < Self.rssConcurrency,
          let feedURL = dequeueNext()
        {
          inFlight.insert(feedURL)
          activeChildren += 1
          group.addTask { [weak self] in
            await self?.processFeedURL(feedURL)
          }
        }

        if activeChildren == 0 {
          if pendingDrainQueue.isEmpty {
            await waitForWork()
            if Task.isCancelled { break }
          }
          continue
        }

        await group.next()
        activeChildren -= 1
      }
      group.cancelAll()
    }
  }

  private func dequeueNext() -> FeedURL? {
    while let next = pendingDrainQueue.first {
      pendingDrainQueue.removeFirst()
      if inFlight.contains(next) { continue }
      if entry(for: next)?.status == .scored { continue }
      return next
    }
    return nil
  }

  private func waitForWork() async {
    if !pendingDrainQueue.isEmpty { return }
    await withCheckedContinuation { continuation in
      if !pendingDrainQueue.isEmpty || Task.isCancelled {
        continuation.resume()
        return
      }
      drainContinuation = continuation
    }
  }

  // MARK: - Pipeline Per Podcast

  private func processFeedURL(_ feedURL: FeedURL) async {
    guard let entry = entry(for: feedURL) else {
      inFlight.remove(feedURL)
      return
    }

    entry.status = .fetching
    let downloadTask = await downloadManager.addURL(feedURL.rawValue)
    entry.fetchToken = downloadTask

    let podcastID = entry.podcastID
    let onDeckID = sharedState.onDeck?.id

    let result = await Self.runPipeline(
      downloadTask: downloadTask,
      entryFeedURL: feedURL,
      podcastID: podcastID,
      onDeckID: onDeckID,
      embedding: contextualEmbedding,
      engine: recommendationEngine,
      repo: repo
    )

    entry.fetchToken = nil
    switch result {
    case .success(let scored):
      entry.scoredEpisodes = scored
      entry.status = .scored
    case .cancelled:
      entry.status = .cancelled
    case .failed(let error):
      entry.status = .failed
      Self.log.caughtError(
        "Pipeline failed for \(feedURL.rawValue)",
        error,
        level: { _ in .info }
      )
    }

    inFlight.remove(feedURL)

    if !pendingDrainQueue.isEmpty {
      drainContinuation?.resume()
      drainContinuation = nil
    }
  }

  // MARK: - Pipeline Static Helper

  private enum PipelineResult {
    case success([ScoredEpisode])
    case cancelled
    case failed(any Error)
  }

  private nonisolated static func runPipeline(
    downloadTask: DownloadTask,
    entryFeedURL: FeedURL,
    podcastID: Podcast.ID?,
    onDeckID: Episode.ID?,
    embedding: ContextualEmbedding,
    engine: RecommendationEngine,
    repo: any Databasing
  ) async -> PipelineResult {
    let feedData: DownloadData
    do {
      feedData = try await downloadTask.downloadFinished()
    } catch is CancellationError {
      return .cancelled
    } catch {
      return .failed(error)
    }

    if Task.isCancelled { return .cancelled }

    let podcastFeed: PodcastFeed
    do {
      podcastFeed = try await PodcastFeed.parse(feedData)
    } catch {
      return .failed(error)
    }

    let unsavedPodcast: UnsavedPodcast
    do {
      unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    } catch {
      return .failed(error)
    }

    let newest = Array(
      podcastFeed.toUnsavedEpisodes()
        .sorted { $0.pubDate > $1.pubDate }
        .prefix(episodesPerPodcast)
    )
    let candidates = await filteredCandidates(
      newest: newest,
      podcastID: podcastID,
      onDeckID: onDeckID,
      repo: repo
    )

    if Task.isCancelled { return .cancelled }

    var scored = [ScoredEpisode](capacity: candidates.count)
    for unsavedEpisode in candidates {
      if Task.isCancelled { return .cancelled }
      let payload = UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
      let vector: [Float]
      do {
        vector = try await EmbeddingService.embeddingVector(for: payload, embedding: embedding)
      } catch is CancellationError {
        return .cancelled
      } catch {
        log.caughtError(
          "Embedding failed for \(payload.toString); skipping",
          error,
          level: { _ in .info }
        )
        continue
      }
      guard let score = engine.similarityScore(forEmbedding: vector) else { continue }
      guard score > scoreFloor else { continue }
      scored.append(ScoredEpisode(episode: payload, score: score, entryFeedURL: entryFeedURL))
    }

    return .success(scored)
  }

  // For unreconciled podcasts (no DB row), every newest-E unsaved episode
  // passes through unchanged. For reconciled-unsubscribed podcasts, we
  // resolve existing rows under that podcast ID with exact (guid, mediaURL)
  // matching and drop any that fail the candidate gate.
  private nonisolated static func filteredCandidates(
    newest: [UnsavedEpisode],
    podcastID: Podcast.ID?,
    onDeckID: Episode.ID?,
    repo: any Databasing
  ) async -> [UnsavedEpisode] {
    guard let podcastID, !newest.isEmpty else { return newest }
    let existing: [Episode]
    do {
      existing = try await repo.episodesMatching(
        podcastID: podcastID,
        guids: newest.map(\.guid),
        mediaURLs: newest.map(\.mediaURL)
      )
    } catch {
      log.caughtError(
        "Candidate-gate lookup failed for podcast \(podcastID)",
        error,
        level: { _ in .info }
      )
      return []
    }

    let existingByGUID = Dictionary(uniqueKeysWithValues: existing.map { ($0.guid, $0) })
    let existingByMediaURL = Dictionary(uniqueKeysWithValues: existing.map { ($0.mediaURL, $0) })

    var result = [UnsavedEpisode](capacity: newest.count)
    for unsaved in newest {
      let match = existingByGUID[unsaved.guid] ?? existingByMediaURL[unsaved.mediaURL]
      if let match, !isDiscoveryCandidate(match, excludingOnDeck: onDeckID) {
        continue
      }
      result.append(unsaved)
    }
    return result
  }

  private nonisolated static func isDiscoveryCandidate(
    _ episode: Episode,
    excludingOnDeck onDeckID: Episode.ID?
  ) -> Bool {
    if let onDeckID, episode.id == onDeckID { return false }
    if episode.currentTime != .zero { return false }
    if episode.finishDate != nil { return false }
    if episode.rating != nil { return false }
    if episode.queueOrder != nil { return false }
    return true
  }

  // MARK: - Computed Outputs

  // Ordered scored picks for the active source. Reads `permanent` /
  // `temporary` / `trendingSourceIndex` / `typedSearchOverlay` and each
  // entry's `status` / `scoredEpisodes`; SwiftUI observation invalidates
  // on any of those mutations.
  var visiblePicks: [ScoredEpisode] {
    guard let activeSource else { return [] }
    return picks(for: activeSource)
  }

  // `.loaded(count)` once any scored picks exist; `.loading` while the
  // pipeline is still warming; `.hidden` when there's nothing to show and
  // nothing in flight.
  var bannerState: BannerState {
    guard let activeSource else { return .hidden }
    return bannerState(for: activeSource)
  }

  // Scored picks for a specific source. Decoupled from `activeSource` so
  // a pushed discovery list keeps rendering its own source even if
  // SearchView later swaps `activeSource` underneath it.
  func picks(for source: Source) -> [ScoredEpisode] {
    let feedURLs = activeFeedURLs(for: source)
    var collected: [ScoredEpisode] = []
    for feedURL in feedURLs {
      guard let entry = entry(for: feedURL), entry.status == .scored else { continue }
      collected.append(contentsOf: entry.scoredEpisodes)
    }
    collected.sort(by: Self.rankComparator)
    return collected
  }

  func bannerState(for source: Source) -> BannerState {
    let feedURLs = activeFeedURLs(for: source)
    guard !feedURLs.isEmpty else { return .hidden }
    let sourcePicks = picks(for: source)
    if !sourcePicks.isEmpty { return .loaded(count: sourcePicks.count) }
    if scoringUnavailable { return .hidden }
    let anyInFlight = feedURLs.contains { url in
      guard let entry = entry(for: url) else { return true }
      switch entry.status {
      case .pending, .fetching, .embedding: return true
      case .scored, .failed, .cancelled: return false
      }
    }
    return anyInFlight ? .loading : .hidden
  }

  private func activeFeedURLs(for source: Source) -> [FeedURL] {
    switch source {
    case .trending:
      return trendingSourceIndex[source] ?? []
    case .search(let query):
      guard let overlay = typedSearchOverlay, overlay.query == query else { return [] }
      return overlay.feedURLs
    }
  }

  // Sort by score desc, then pubDate desc, then GUID, then mediaURL as
  // the final tie-breaker so the order is fully deterministic.
  fileprivate static func rankComparator(_ lhs: ScoredEpisode, _ rhs: ScoredEpisode) -> Bool {
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    if lhs.episode.pubDate != rhs.episode.pubDate {
      return lhs.episode.pubDate > rhs.episode.pubDate
    }
    if lhs.episode.mediaGUID.guid != rhs.episode.mediaGUID.guid {
      return lhs.episode.mediaGUID.guid > rhs.episode.mediaGUID.guid
    }
    return lhs.episode.mediaGUID.mediaURL.rawValue.absoluteString
      > rhs.episode.mediaGUID.mediaURL.rawValue.absoluteString
  }

  // MARK: - Observation Helpers

  private func firstObservationEmission(
    feedURLs: [FeedURL],
    iTunesIDs: [ITunesPodcastID]
  ) async -> [PodcastWithEpisodeMetadata<ListablePodcast>] {
    guard !feedURLs.isEmpty || !iTunesIDs.isEmpty else { return [] }
    do {
      let observation = observatory.listablePodcastsWithEpisodeMetadata(
        feedURLs,
        iTunesIDs: iTunesIDs
      )
      for try await snapshot in observation {
        return snapshot
      }
    } catch {
      Self.log.caughtError(
        "Reconciliation observation failed",
        error,
        level: { _ in .info }
      )
    }
    return []
  }
}

// MARK: - CachedPodcastEntry

@Observable @MainActor
private final class CachedPodcastEntry {
  enum Status: Equatable {
    case pending
    case fetching
    case embedding
    case scored
    case failed
    case cancelled
  }

  let feedURL: FeedURL
  let podcastID: Podcast.ID?
  var status: Status = .pending
  var scoredEpisodes: [SearchRecommendationCollector.ScoredEpisode] = []
  @ObservationIgnored var fetchToken: DownloadTask?

  init(feedURL: FeedURL, podcastID: Podcast.ID?) {
    self.feedURL = feedURL
    self.podcastID = podcastID
  }

  func cancel() async {
    let token = fetchToken
    fetchToken = nil
    status = .cancelled
    await token?.cancel()
  }
}

// MARK: - TypedSearchOverlay

@MainActor
private final class TypedSearchOverlay {
  let query: String
  let feedURLs: [FeedURL]

  init(query: String, feedURLs: [FeedURL]) {
    self.query = query
    self.feedURLs = feedURLs
  }
}
