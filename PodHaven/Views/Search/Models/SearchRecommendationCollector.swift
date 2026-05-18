// Copyright Justin Bishop, 2026

import CoreMedia
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Tagged

// MARK: - SearchRecommendationCollector

// Lives for the duration of the Search tab visit. Owns RSS fetch + embed +
// score work for two surfaces:
//
//   - Top-category trending: chip switches reuse a long-lived shared podcast
//     cache so a podcast that appears in multiple chips is downloaded and
//     scored once.
//   - Typed search: each debounced query builds a per-query overlay that
//     reuses already-scored shared podcasts and discards query-only misses
//     when the query changes.
//
// Cancellation rules differ: trending work isn't cancelled when the active
// chip switches, only when the collector tears down. Typed-search overlay
// work is cancelled when the query changes.
@Observable @MainActor
final class SearchRecommendationCollector {
  nonisolated private static let log = Log.as(LogSubsystem.SearchView.recommendations)

  // MARK: - Tunable Caps

  // First P podcasts from each source ranking are eligible. We don't
  // backfill deeper than P; lower-ranked source results shouldn't become
  // "top picks" just because the first page was already subscribed.
  nonisolated static let podcastCap = 25

  // Newest E episodes per podcast feed enter the candidate gate / embedding
  // pipeline.
  nonisolated static let episodesPerPodcast = 10

  // Discovery removes freshness, so neutral content clusters around the
  // remapped 0.5 baseline. UpNext's 0.1 floor is for a freshness-modulated
  // composite and doesn't apply here.
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
  }

  // MARK: - Dependencies

  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.searchDiscoveryDownloadManager)
  private var downloadManager
  @ObservationIgnored @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.taskPriority) private var taskPriority

  // MARK: - Observed Outputs

  // Whichever surface SearchView is currently rendering. Set by
  // SearchViewModel; changes the banner / discovery list reads only.
  var activeSource: Source? = nil

  // `.hidden` when no source, no podcasts, or scoring unavailable;
  // `.loading` while the pipeline is still warming; `.loaded(count)` once
  // at least one pick is ready.
  var bannerState: BannerState = .hidden

  // Ordered scored picks for the active source. The discovery list reads
  // this directly. Row actions in the list call `removePick` to drop
  // entries after a successful materialization or mutation.
  private(set) var visiblePicks: [ScoredEpisode] = []

  // MARK: - Internal State

  // Shared cache that survives top-category chip switches inside one
  // Search-tab visit. Keyed by the canonical (reconciled) feed URL.
  // Typed-search-only podcasts are NOT promoted here.
  private var sharedPodcastCache: [FeedURL: CachedPodcastEntry] = [:]

  // Per top-category source: the ordered feed URLs selected from that
  // category's current iTunes result snapshot. Points into the shared
  // cache.
  private var trendingSourceIndex: [Source: [FeedURL]] = [:]

  // Current typed-search overlay. Holds feed URLs and any entries that
  // don't already exist in sharedPodcastCache; replaced on query change.
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

  // Episode IDs the discovery list has already acted on. Survives cache
  // updates so post-action removal isn't undone by later re-scores.
  private var removedMediaGUIDs: Set<MediaGUID> = []

  // MARK: - Lifecycle

  init() {}

  // MARK: - Public API

  // Update which source the banner / discovery list reads from. Does not
  // trigger pipeline work; pair with `recordSourcePodcasts` for that.
  func setActiveSource(_ source: Source?) {
    Self.log.debug("Active source -> \(String(describing: source))")
    guard source != activeSource else { return }
    activeSource = source
    refreshOutputs()
  }

  // Called by SearchViewModel after iTunes search / trending returns. The
  // collector reconciles `podcasts` against the DB, drops subscribed ones,
  // takes the first 25 survivors as the source's ranking, and queues the
  // missing podcasts for RSS+embed+score work after the 1 s stable-source
  // debounce. Typed-search recordings replace the prior overlay if
  // `source.query` differs.
  func recordSourcePodcasts(
    source: Source,
    podcasts: [PodcastWithEpisodeMetadata<ListedPodcast>]
  ) {
    Self.log.debug(
      "Recording source \(String(describing: source)) with \(podcasts.count) podcasts"
    )

    let debouncer = debouncers[source] ?? Debounce(duration: Self.stableSourceDebounce)
    debouncers[source] = debouncer

    let capped = podcasts.prefix(Self.podcastCap).map { $0 }
    debouncer { [weak self] in
      guard let self else { return }
      await self.reconcileAndIngest(source: source, podcasts: capped)
    }
  }

  // The discovery list calls this after a successful row action that
  // materialized or mutated the episode. We drop the entry instead of
  // live-converting it in place; the row's episode detail handles the
  // unsaved→saved transition on its own.
  func removePick(mediaGUID: MediaGUID) {
    Self.log.debug("Removing pick \(mediaGUID)")
    removedMediaGUIDs.insert(mediaGUID)
    refreshOutputs()
  }

  // Called by SearchViewModel when the Search tab is actually torn down
  // (not on a navigation push that's still rooted in Search). Cancels all
  // in-flight RSS downloads and clears every cache layer.
  func teardown() {
    Self.log.debug("Teardown")

    drainTask?.cancel()
    drainTask = nil
    drainContinuation?.resume()
    drainContinuation = nil
    pendingDrainQueue.removeAll()
    inFlight.removeAll()

    for debouncer in debouncers.values { debouncer.cancel() }
    debouncers.removeAll()

    let entriesToCancel =
      Array(sharedPodcastCache.values)
      + Array(typedSearchOverlay?.localEntries.values ?? [:].values)
    sharedPodcastCache.removeAll()
    trendingSourceIndex.removeAll()
    let prior = typedSearchOverlay
    typedSearchOverlay = nil
    removedMediaGUIDs.removeAll()

    Task { [entriesToCancel, prior] in
      for entry in entriesToCancel { await entry.cancel() }
      await prior?.cancel()
    }

    activeSource = nil
    bannerState = .hidden
    visiblePicks = []
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
        if sharedPodcastCache[feedURL] == nil {
          sharedPodcastCache[feedURL] = CachedPodcastEntry(
            feedURL: feedURL,
            podcastID: podcastIDs[feedURL]
          )
        }
        scheduleDrain(for: feedURL)
      }

    case .search(let query):
      if let existing = typedSearchOverlay, existing.query == query {
        existing.feedURLs = feedURLs
      } else {
        let prior = typedSearchOverlay
        typedSearchOverlay = TypedSearchOverlay(query: query, feedURLs: feedURLs)
        if let prior {
          for feedURL in prior.localEntries.keys {
            pendingDrainQueue.removeAll { $0 == feedURL }
          }
          Task { await prior.cancel() }
        }
      }
      guard let overlay = typedSearchOverlay else { return }
      for feedURL in feedURLs {
        if sharedPodcastCache[feedURL] == nil, overlay.localEntries[feedURL] == nil {
          overlay.localEntries[feedURL] = CachedPodcastEntry(
            feedURL: feedURL,
            podcastID: podcastIDs[feedURL]
          )
        }
        scheduleDrain(for: feedURL)
      }
    }

    refreshOutputs()
    ensureDrainTaskRunning()
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
    if let entry = sharedPodcastCache[feedURL] { return entry }
    return typedSearchOverlay?.localEntries[feedURL]
  }

  // MARK: - Drain Task

  private func ensureDrainTaskRunning() {
    if let drainTask, !drainTask.isCancelled { return }
    drainTask = Task(priority: taskPriority(.utility)) { [weak self] in
      await self?.runDrainLoop()
    }
  }

  private func runDrainLoop() async {
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
    refreshOutputs()

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

    let newest: [UnsavedEpisode] =
      podcastFeed.toUnsavedEpisodes()
      .sorted { $0.pubDate > $1.pubDate }
      .prefix(episodesPerPodcast)
      .map { $0 }
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
      scored.append(ScoredEpisode(episode: payload, score: score))
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
      if let match, !match.isDiscoveryCandidate(excludingOnDeck: onDeckID) {
        continue
      }
      result.append(unsaved)
    }
    return result
  }

  // MARK: - Output Refresh

  // Recomputes banner state and visible picks from whichever source is
  // currently active. Called any time cache state changes: new recordings,
  // new scored entries, active-source switches, post-action removals.
  private func refreshOutputs() {
    guard let activeSource else {
      bannerState = .hidden
      visiblePicks = []
      return
    }

    let feedURLs = activeFeedURLs(for: activeSource)
    guard !feedURLs.isEmpty else {
      bannerState = .hidden
      visiblePicks = []
      return
    }

    var collected: [ScoredEpisode] = []
    var anyInFlight = false
    for feedURL in feedURLs {
      guard let entry = entry(for: feedURL) else {
        anyInFlight = true
        continue
      }
      switch entry.status {
      case .pending, .fetching, .embedding:
        anyInFlight = true
      case .failed, .cancelled:
        continue
      case .scored:
        collected.append(contentsOf: entry.scoredEpisodes)
      }
    }

    collected.removeAll { removedMediaGUIDs.contains($0.id) }
    collected.sort(by: Self.rankComparator)

    if collected.isEmpty {
      bannerState = anyInFlight ? .loading : .hidden
      visiblePicks = []
    } else {
      bannerState = .loaded(count: collected.count)
      visiblePicks = collected
    }
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

@MainActor
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
  var fetchToken: DownloadTask?

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
  var feedURLs: [FeedURL]
  var localEntries: [FeedURL: CachedPodcastEntry]

  init(query: String, feedURLs: [FeedURL], localEntries: [FeedURL: CachedPodcastEntry] = [:]) {
    self.query = query
    self.feedURLs = feedURLs
    self.localEntries = localEntries
  }

  func cancel() async {
    let toCancel = Array(localEntries.values)
    localEntries.removeAll()
    for entry in toCancel { await entry.cancel() }
  }
}

// MARK: - Episode Candidate Gate

extension Episode {
  fileprivate func isDiscoveryCandidate(excludingOnDeck onDeckID: Episode.ID?) -> Bool {
    if let onDeckID, id == onDeckID { return false }
    if currentTime != .zero { return false }
    if finishDate != nil { return false }
    if rating != nil { return false }
    if queueOrder != nil { return false }
    return true
  }
}
