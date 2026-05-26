// Copyright Justin Bishop, 2026

import Algorithms
import CoreMedia
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import OrderedCollections
import Tagged

// MARK: - SearchRecommendationCollector

// Trending podcasts live in a shared cache across chip switches; typed-search
// adds a per-query overlay that's discarded when the query changes.
@Observable @MainActor
final class SearchRecommendationCollector {
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.taskPriority) private var taskPriority

  @ObservationIgnored private let downloadManager: DownloadManager

  nonisolated private static let log = Log.as(LogSubsystem.SearchView.recommendations)

  // MARK: - Tunable Caps

  nonisolated static let podcastCap = 25
  nonisolated static let episodesPerPodcast = 10

  // Discovery removes freshness, so neutral content clusters around 0.5.
  nonisolated static let scoreFloor: Float = 0.5

  // Embedding serializes through ContextualEmbedding; wider RSS concurrency
  // only buys faster first-paint.
  nonisolated static let rssConcurrency = 8

  // Held between iTunes result emit and RSS fan-out; independent of the
  // 400 ms search-query debounce.
  nonisolated static let stableSourceDebounce: Duration = .seconds(1)

  // MARK: - Source

  enum Source: Sendable, Hashable {
    struct Trending: Sendable, Hashable {
      let genreID: Int?
      let title: String
    }

    case search(query: String)
    case trending(Trending)

    var discoveryListTitle: String {
      switch self {
      case .search(let query): return "\"\(query)\""
      case .trending(let trending): return trending.genreID == nil ? "Top picks" : trending.title
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
  }

  // MARK: - Observed Outputs

  var activeSource: Source? = nil

  // MARK: - Internal State

  // Survives chip switches and query changes for the collector's lifetime.
  private var permanent: IdentifiedArrayOf<CachedPodcastEntry> = []

  // Owned by the current typed-search query. Purged with in-flight downloads
  // cancelled when the query changes.
  private var temporary: IdentifiedArrayOf<CachedPodcastEntry> = []

  private var trendingSourceIndex: [Source.Trending: [FeedURL]] = [:]
  private var typedSearchOverlay: TypedSearchOverlay? = nil

  // Per-chip — results land at independent times and don't race each other.
  private var trendingDebouncers: [Source.Trending: Debounce] = [:]

  // Shared across queries so `foo → bar` cancels foo's pending action before
  // it can fire after bar has taken over the overlay.
  private var typedSearchDebouncer: Debounce?

  private var drainTask: Task<Void, Never>?
  private var pendingDrainQueue: OrderedSet<FeedURL> = []
  private var drainContinuation: CheckedContinuation<Void, Never>?
  private var inFlight: Set<FeedURL> = []

  // `.unavailable` surfaces .hidden on the banner and lets the drain proceed
  // instead of blocking forever.
  private enum ScoringAvailability: Equatable {
    case unknown
    case ready
    case unavailable
  }
  private var scoringAvailability: ScoringAvailability = .unknown

  // Watches for engine warm-up after surfacing .unavailable so we can re-queue
  // finished entries.
  private var scoringContextWatcherTask: Task<Void, Never>?

  // MARK: - Lifecycle

  init() {
    downloadManager = DownloadManager(session: Container.shared.podcastFeedSession())
  }

  // MARK: - Public API

  // Leaving typed search releases the overlay so a stale query can't keep
  // firing after the user has moved on. Pair with `recordSourcePodcasts`.
  func setActiveSource(_ source: Source?) {
    Self.log.debug("Active source -> \(String(describing: source))")
    guard source != activeSource else { return }
    let previous = activeSource
    activeSource = source
    if case .search = previous {
      switch source {
      case .search: break
      case .trending, .none: clearTypedSearchOverlay()
      }
    }
  }

  // Caps to `podcastCap`, drops subscribed rows after DB reconciliation (no
  // backfill into the deeper ranking), and queues survivors for RSS+embed
  // +score after `stableSourceDebounce`.
  func recordSourcePodcasts(
    source: Source,
    podcasts: [PodcastWithEpisodeMetadata<ListedPodcast>]
  ) {
    Self.log.debug(
      "Recording source \(String(describing: source)) with \(podcasts.count) podcasts"
    )

    let debouncer: Debounce
    switch source {
    case .trending(let trending):
      debouncer = trendingDebouncers[trending] ?? Debounce(duration: Self.stableSourceDebounce)
      trendingDebouncers[trending] = debouncer
    case .search:
      let shared = typedSearchDebouncer ?? Debounce(duration: Self.stableSourceDebounce)
      typedSearchDebouncer = shared
      debouncer = shared
    }

    let capped = Array(podcasts.prefix(Self.podcastCap))
    debouncer { [weak self] in
      guard let self else { return }
      await self.reconcileAndIngest(source: source, podcasts: capped)
    }
  }

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
    scoringAvailability = .unknown

    let toCancel = Array(permanent) + Array(temporary)
    permanent.removeAll()
    temporary.removeAll()
    trendingSourceIndex.removeAll()
    typedSearchOverlay = nil
    // Dropping Debounce references doesn't cancel their pending sleeps —
    // those run to the deadline and re-enter the stale action.
    for debouncer in trendingDebouncers.values { debouncer.cancel() }
    trendingDebouncers.removeAll()
    typedSearchDebouncer?.cancel()
    typedSearchDebouncer = nil
    pendingDrainQueue.removeAll()
    inFlight.removeAll()
    activeSource = nil

    // drainTask cancellation propagates to processFeedURL children which
    // clear their fetchTokens before this Task body runs. Go through the
    // manager so active downloads get cancelled regardless.
    Task { [downloadManager] in
      await downloadManager.cancelAllDownloads()
      for entry in toCancel { await entry.cancel() }
    }
  }

  private func clearTypedSearchOverlay() {
    // Debouncer is included: between recordSourcePodcasts and its reconcile
    // firing, the pending debounce is the only typed-search state alive.
    guard typedSearchDebouncer != nil || typedSearchOverlay != nil || !temporary.isEmpty
    else { return }
    Self.log.debug("Clearing typed-search overlay")
    typedSearchDebouncer?.cancel()
    typedSearchDebouncer = nil
    typedSearchOverlay = nil
    let toCancel = Array(temporary)
    let purgedURLs = Set(temporary.ids)
    temporary.removeAll()
    pendingDrainQueue.removeAll { purgedURLs.contains($0) }
    Task {
      for entry in toCancel { await entry.cancel() }
    }
  }

  // Caller's `feedURL` comes from `ListedEpisode.feedURL` (parsed
  // atom:link self / itunes:new-feed-url) and can differ from the cache key,
  // so fall back to a mediaGUID scan if the direct lookup misses.
  func removePick(feedURL: FeedURL, mediaGUID: MediaGUID) {
    Self.log.debug("Removing pick \(mediaGUID)")
    if let entry = permanent[id: feedURL] ?? temporary[id: feedURL],
      entry.scoredEpisodes.contains(where: { $0.id == mediaGUID })
    {
      entry.scoredEpisodes.removeAll { $0.id == mediaGUID }
      return
    }
    for entry in chain(permanent, temporary)
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
    var reconciledITunesIDs: [FeedURL: ITunesPodcastID] = [:]
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

      // Canonical DB feedURL is the dedup key the shared cache uses across
      // categories.
      let canonicalFeedURL = bridged?.podcast.feedURL ?? slotURL
      reconciledFeedURLs.append(canonicalFeedURL)
      if let bridged { reconciledPodcastIDs[canonicalFeedURL] = bridged.podcast.id }
      // Threaded into the pick's UnsavedPodcast so the downstream upsert can
      // hit the by-iTunesID branch even when RSS publishes a different
      // atom:self / itunes:new-feed-url.
      if let iTunesID = bridged?.podcast.iTunesID ?? entry.podcast.iTunesID {
        reconciledITunesIDs[canonicalFeedURL] = iTunesID
      }
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
      podcastIDs: reconciledPodcastIDs,
      iTunesIDs: reconciledITunesIDs
    )
  }

  private func applyReconciledRanking(
    source: Source,
    feedURLs: [FeedURL],
    podcastIDs: [FeedURL: Podcast.ID],
    iTunesIDs: [FeedURL: ITunesPodcastID]
  ) {
    switch source {
    case .trending(let trending):
      trendingSourceIndex[trending] = feedURLs
      for feedURL in feedURLs {
        if let promoted = temporary.remove(id: feedURL) {
          permanent[id: feedURL] = promoted
        } else if permanent[id: feedURL] == nil {
          permanent[id: feedURL] = CachedPodcastEntry(
            feedURL: feedURL,
            podcastID: podcastIDs[feedURL],
            iTunesID: iTunesIDs[feedURL]
          )
        }
        scheduleDrain(for: feedURL)
      }

    case .search(let query):
      let previousQuery = typedSearchOverlay?.query
      typedSearchOverlay = TypedSearchOverlay(query: query, feedURLs: feedURLs)
      if previousQuery != query {
        // Survivors keep their in-flight work instead of being orphaned by
        // the inFlight guard in `scheduleDrain`.
        pruneTemporary(keeping: Set(feedURLs))
      }
      for feedURL in feedURLs {
        if permanent[id: feedURL] == nil, temporary[id: feedURL] == nil {
          temporary[id: feedURL] = CachedPodcastEntry(
            feedURL: feedURL,
            podcastID: podcastIDs[feedURL],
            iTunesID: iTunesIDs[feedURL]
          )
        }
        scheduleDrain(for: feedURL)
      }
    }

    ensureDrainTaskRunning()
  }

  private func pruneTemporary(keeping survivors: Set<FeedURL>) {
    guard !temporary.isEmpty else { return }
    var toCancel: [CachedPodcastEntry] = []
    var purgedURLs: Set<FeedURL> = []
    for entry in temporary where !survivors.contains(entry.feedURL) {
      toCancel.append(entry)
      purgedURLs.insert(entry.feedURL)
    }
    guard !purgedURLs.isEmpty else { return }
    for url in purgedURLs { temporary.remove(id: url) }
    pendingDrainQueue.removeAll { purgedURLs.contains($0) }
    Task {
      for entry in toCancel { await entry.cancel() }
    }
  }

  private func scheduleDrain(for feedURL: FeedURL) {
    guard !inFlight.contains(feedURL) else { return }
    let status = entry(for: feedURL)?.status
    guard status != .scored else { return }
    guard pendingDrainQueue.append(feedURL).inserted else { return }
    drainContinuation?.resume()
    drainContinuation = nil
  }

  private func entry(for feedURL: FeedURL) -> CachedPodcastEntry? {
    if let entry = permanent[id: feedURL] { return entry }
    return temporary[id: feedURL]
  }

  private func awaitScoringContext() async {
    if recommendationEngine.hasScoringContext {
      scoringAvailability = .ready
      return
    }
    recommendationEngine.start()
    // AppLauncher pre-starts the engine, so the no-context revision can
    // already be in the past — don't subscribe to a stream whose only emit
    // would be the bootstrap replay.
    if recommendationEngine.scoringRevision > 0 {
      // Re-check: the engine could have warmed between the first read and
      // now; setting .unavailable here would briefly hide the banner before
      // the watcher's first emit flips us back to .ready.
      if recommendationEngine.hasScoringContext {
        scoringAvailability = .ready
        return
      }
      scoringAvailability = .unavailable
      startScoringContextWatcherIfNeeded()
      return
    }
    for await revision in recommendationEngine.$scoringRevision.stream() {
      if Task.isCancelled { return }
      if recommendationEngine.hasScoringContext {
        scoringAvailability = .ready
        return
      }
      if revision == 0 { continue }
      scoringAvailability = .unavailable
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
    // Don't dropFirst: engine state can change between the caller flipping
    // to .unavailable and this watcher subscribing.
    for await _ in recommendationEngine.$scoringRevision.stream() {
      if Task.isCancelled { return }
      if recommendationEngine.hasScoringContext {
        handleScoringContextBecameAvailable()
        return
      }
    }
  }

  private func handleScoringContextBecameAvailable() {
    scoringAvailability = .ready
    scoringContextWatcherTask = nil
    let allEntries = Array(permanent) + Array(temporary)
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
    // Without a hydrated cache, every candidate scores nil, entries finish
    // empty-and-.scored, and nothing retries them.
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
    let iTunesID = entry.iTunesID
    let onDeckID = sharedState.onDeck?.id

    let result = await Self.runPipeline(
      downloadTask: downloadTask,
      podcastID: podcastID,
      iTunesID: iTunesID,
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

    // If a concurrent overlay purge swapped in a new entry, scheduleDrain
    // would have bailed on the inFlight guard, leaving it stuck .pending.
    if let current = self.entry(for: feedURL), current !== entry, current.status != .scored {
      scheduleDrain(for: feedURL)
    }

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
    podcastID: Podcast.ID?,
    iTunesID: ITunesPodcastID?,
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
      unsavedPodcast = try podcastFeed.toUnsavedPodcast(iTunesID: iTunesID)
    } catch {
      return .failed(error)
    }

    let newest = Array(
      podcastFeed.toUnsavedEpisodes()
        .sorted { $0.pubDate > $1.pubDate }
        .prefix(episodesPerPodcast)
    )
    let candidates: [UnsavedEpisode]
    do {
      candidates = try await filteredCandidates(
        newest: newest,
        podcastID: podcastID,
        onDeckID: onDeckID,
        repo: repo
      )
    } catch {
      return .failed(error)
    }

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
      scored.append(ScoredEpisode(episode: payload, score: score))
    }

    return .success(scored)
  }

  // Drops episodes whose existing DB row fails the candidate gate. Unreconciled
  // podcasts (no DB row) pass through unchanged.
  private nonisolated static func filteredCandidates(
    newest: [UnsavedEpisode],
    podcastID: Podcast.ID?,
    onDeckID: Episode.ID?,
    repo: any Databasing
  ) async throws -> [UnsavedEpisode] {
    guard let podcastID, !newest.isEmpty else { return newest }
    let existing = try await repo.episodesMatching(
      podcastID: podcastID,
      guids: newest.map(\.guid),
      mediaURLs: newest.map(\.mediaURL)
    )

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

  var visiblePicks: [ScoredEpisode] {
    guard let activeSource else { return [] }
    return picks(for: activeSource)
  }

  var bannerState: BannerState {
    guard let activeSource else { return .hidden }
    return bannerState(for: activeSource)
  }

  // Decoupled from `activeSource` so a pushed discovery list keeps rendering
  // its own source even if SearchView later swaps `activeSource`.
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
    if scoringAvailability == .unavailable { return .hidden }
    let anyInFlight = feedURLs.contains { url in
      guard let entry = entry(for: url) else { return true }
      switch entry.status {
      case .pending, .fetching: return true
      case .scored, .failed, .cancelled: return false
      }
    }
    return anyInFlight ? .loading : .hidden
  }

  private func activeFeedURLs(for source: Source) -> [FeedURL] {
    switch source {
    case .trending(let trending):
      return trendingSourceIndex[trending] ?? []
    case .search(let query):
      guard let overlay = typedSearchOverlay, overlay.query == query else { return [] }
      return overlay.feedURLs
    }
  }

  // mediaURL is the final tie-breaker so ordering is deterministic.
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
private final class CachedPodcastEntry: Identifiable {
  enum Status: Equatable {
    case pending
    case fetching
    case scored
    case failed
    case cancelled
  }

  let feedURL: FeedURL
  let podcastID: Podcast.ID?
  let iTunesID: ITunesPodcastID?
  var status: Status = .pending
  var scoredEpisodes: [SearchRecommendationCollector.ScoredEpisode] = []
  @ObservationIgnored var fetchToken: DownloadTask?

  var id: FeedURL { feedURL }

  init(feedURL: FeedURL, podcastID: Podcast.ID?, iTunesID: ITunesPodcastID?) {
    self.feedURL = feedURL
    self.podcastID = podcastID
    self.iTunesID = iTunesID
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
