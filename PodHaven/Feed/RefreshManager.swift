// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Logging
import Tagged

extension Container {
  var refreshManager: Factory<RefreshManager> {
    Factory(self) { RefreshManager() }.scope(.cached)
  }
}

struct RefreshManager {
  enum Trigger: Sendable {
    case scheduled
    case user
  }

  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.dateProvider) private var dateProvider
  @DynamicInjected(\.embeddingProcessor) private var embeddingProcessor
  @DynamicInjected(\.publisherTranscriptProcessor) private var publisherTranscriptProcessor
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.transcriptionProcessor) private var transcriptionProcessor

  private var userNotificationManager: UserNotificationManager {
    Container.shared.userNotificationManager()
  }

  private static let log = Log.as(LogSubsystem.Feed.refreshManager)

  // A scheduled refresh skips a failing feed for initialBackoff, doubling with
  // each consecutive failure up to maximumBackoff.
  private static let initialBackoff: Duration = .hours(1)
  private static let maximumBackoff: Duration = .hours(24)
  // Cancellation and lost connectivity say nothing about the feed.
  private static let nonFeedURLErrorCodes: Set<URLError.Code> = [
    .cancelled,
    .notConnectedToInternet,
    .networkConnectionLost,
    .dataNotAllowed,
    .internationalRoamingOff,
    .callIsActive,
  ]

  private let downloadManager: DownloadManager
  private let inFlight = ThreadSafe<Set<URL>>([])
  // Feeds that fail to parse stay stale and keep retrying, so warn once per process.
  private let reportedUndecodableFeeds = ThreadSafe<Set<URL>>([])
  // A feed whose new URL another podcast holds tries to move on every refresh,
  // so warn once per process.
  private let reportedFeedURLCollisions = ThreadSafe<Set<URL>>([])

  // MARK: - Initialization

  fileprivate init() {
    downloadManager = DownloadManager(
      session: Container.shared.podcastFeedSession(),
      maxConcurrentDownloads: 8
    )
  }

  // MARK: - Refresh Management

  func performRefresh(
    trigger: Trigger,
    stalenessThreshold: Duration,
    filter: SQLExpression = AppDB.noOp,
    limit: Int = Int.max
  ) async throws {
    Self.log.debug(
      """
      performRefresh:
        stalenessThreshold: \(stalenessThreshold)
      """
    )

    let now = dateProvider.now
    let backoffFilter: SQLExpression
    switch trigger {
    case .scheduled:
      backoffFilter =
        Podcast.Columns.refreshBackoffUntil == nil || Podcast.Columns.refreshBackoffUntil <= now
    case .user:
      backoffFilter = AppDB.noOp
    }
    let stalePodcasts = try await repo.allPodcasts(
      Podcast.Columns.lastUpdate < now.advanced(by: -stalenessThreshold.asTimeInterval)
        && backoffFilter
        && filter,
      // Failing feeds go last so they can't take a healthy feed's slot.
      order: [Podcast.Columns.refreshFailureCount.asc, Podcast.Columns.lastUpdate.asc],
      limit: limit
    )
    Self.log.debug(
      "performRefresh: fetched \(stalePodcasts.count) stale podcasts (limit: \(limit))"
    )

    let collected = await withTaskGroup(
      of: PendingFlush?.self,
      returning: [PendingFlush].self
    ) { group in
      for podcast in stalePodcasts {
        group.addTask { [podcast] in
          do {
            return try await performRefreshCycle(podcast: podcast)
          } catch {
            Self.log.caughtError(
              "Failed to refresh podcast: \(podcast.toString)",
              error,
              level: .info
            )
            return nil
          }
        }
      }
      var results = [PendingFlush](capacity: stalePodcasts.count)
      for await result in group {
        if let result {
          results.append(result)
        }
      }
      return results
    }

    if !collected.isEmpty {
      let urls = collected.map(\.url)
      // Task to execute even inside cancellation: ensures the results
      // collected for series that already finished refreshing get flushed
      // before performRefresh returns, so the next cycle sees them as fresh
      // or backed off. inFlight URLs stay claimed until the flush commits (or
      // fails) so a racing refresh cannot re-fetch a series whose result
      // hasn't yet hit the DB.
      await Task {
        defer { inFlight { state in for url in urls { state.remove(url) } } }
        do {
          try await flush(collected)
        } catch {
          Self.log.caughtError(
            "performRefresh: failed to flush \(collected.count) refresh results",
            error
          )
        }
      }
      .value
    }

    await publisherTranscriptProcessor.makeForegroundProgress()
    Self.log.debug("performRefresh: completed")
  }

  func refreshSeries(podcast: Podcast) async throws {
    Self.log.trace(
      """
      refreshSeries:
        podcast: \(podcast.toString)
      """
    )

    if let pending = try await performRefreshCycle(podcast: podcast) {
      defer { inFlight { $0.remove(pending.url) } }
      // Record the refresh even if the caller is cancelled after the feed write.
      try await Task { try await flush([pending]) }.value
    }
    await publisherTranscriptProcessor.makeForegroundProgress()
  }

  // MARK: - Private Helpers

  private enum RefreshResult {
    case refreshed(lastUpdate: Date, feedValidators: HTTPValidators?)
    case failed(failureCount: Int, backoffUntil: Date)
  }

  private typealias PendingFlush = (id: Podcast.ID, url: URL, result: RefreshResult)

  private func flush(_ pendingFlushes: [PendingFlush]) async throws {
    var refreshes: [(id: Podcast.ID, lastUpdate: Date, feedValidators: HTTPValidators?)] = []
    var failures: [(id: Podcast.ID, failureCount: Int, backoffUntil: Date)] = []
    for pending in pendingFlushes {
      switch pending.result {
      case .refreshed(let lastUpdate, let feedValidators):
        refreshes.append((pending.id, lastUpdate, feedValidators))
      case .failed(let failureCount, let backoffUntil):
        failures.append((pending.id, failureCount, backoffUntil))
      }
    }
    if !refreshes.isEmpty {
      try await repo.updateLastUpdates(refreshes)
    }
    if !failures.isEmpty {
      try await repo.recordRefreshFailures(failures)
    }
  }

  private func failure(of podcast: Podcast) -> PendingFlush {
    let failureCount = podcast.refreshFailureCount + 1
    var backoff = Self.initialBackoff
    var doublings = failureCount - 1
    while doublings > 0, backoff < Self.maximumBackoff {
      backoff *= 2
      doublings -= 1
    }
    let backoffUntil = dateProvider.now.advanced(
      by: min(backoff, Self.maximumBackoff).asTimeInterval
    )
    Self.log.debug(
      "failure: \(podcast.toString) failed \(failureCount) times in a row, backing off until \(backoffUntil)"
    )
    return PendingFlush(
      id: podcast.id,
      url: podcast.feedURL.rawValue,
      result: .failed(failureCount: failureCount, backoffUntil: backoffUntil)
    )
  }

  // When a PendingFlush is returned, the caller owns removing url from
  // inFlight after the batched flush commits — otherwise a racing refresh of
  // the still-stale row could slip through the gap.
  private func performRefreshCycle(
    podcast: Podcast
  ) async throws -> PendingFlush? {
    let url = podcast.feedURL.rawValue

    let alreadyInFlight = inFlight { !$0.insert(url).inserted }
    if alreadyInFlight {
      Self.log.debug(
        "performRefreshCycle: \(podcast.toString) already in-flight; skipping"
      )
      return nil
    }

    var releaseOnExit = true
    defer { if releaseOnExit { inFlight { $0.remove(url) } } }

    let feedValidators = podcast.feedValidators
    let downloadTask = await downloadManager.addURL(url, validators: feedValidators)
    let downloadData: DownloadData
    let podcastFeed: PodcastFeed
    do {
      downloadData = try await downloadTask.downloadFinished()
      podcastFeed = try await PodcastFeed.parse(downloadData)
    } catch let error as HTTPStatusError where error.statusCode == 304 && feedValidators != nil {
      Self.log.trace("performRefreshCycle: \(podcast.toString) not modified")
      releaseOnExit = false
      return PendingFlush(
        id: podcast.id,
        url: url,
        result: .refreshed(lastUpdate: dateProvider.now, feedValidators: feedValidators)
      )
    } catch {
      let level: Logger.Level
      switch error {
      case is DecodingError, PodcastFeedError.notXML:
        level = reportedUndecodableFeeds { $0.insert(url).inserted } ? .warning : .notice
      default:
        level = .notice
      }
      Self.log.caughtError(
        """
        Failed to parse podcast feed
          Podcast: \(podcast.toString)
          FeedURL: \(podcast.feedURL)
        """,
        error,
        level: level
      )
      if Task.isCancelled || error is CancellationError { return nil }
      if let urlError = error as? URLError, Self.nonFeedURLErrorCodes.contains(urlError.code) {
        return nil
      }
      releaseOnExit = false
      return failure(of: podcast)
    }

    let existingEpisodes = try await repo.feedMergeEpisodes(
      podcastID: podcast.id,
      matching: podcastFeed.episodeMediaGUIDs
    )

    var feedURL = podcastFeed.updatedFeedURL
    if feedURL != podcast.feedURL,
      !(try await repo.allPodcasts(Podcast.Columns.feedURL == feedURL).isEmpty)
    {
      if reportedFeedURLCollisions({ $0.insert(url).inserted }) {
        Self.log.warning(
          """
          Feed moved to a URL another podcast holds, keeping its current URL
            Podcast: \(podcast.toString)
            MovedTo: \(feedURL)
          """
        )
      }
      feedURL = podcast.feedURL
    }

    guard
      let lastUpdate = await applyParsedFeed(
        podcast: podcast,
        podcastFeed: podcastFeed,
        feedURL: feedURL,
        existingEpisodes: existingEpisodes
      )
    else {
      if Task.isCancelled { return nil }
      releaseOnExit = false
      return failure(of: podcast)
    }
    releaseOnExit = false
    return PendingFlush(
      id: podcast.id,
      url: url,
      result: .refreshed(
        lastUpdate: lastUpdate,
        // Validators from the old URL don't describe the feed at its new one.
        feedValidators: feedURL == podcast.feedURL ? downloadData.validators : nil
      )
    )
  }

  private func applyParsedFeed(
    podcast: Podcast,
    podcastFeed: PodcastFeed,
    feedURL: FeedURL,
    existingEpisodes: [FeedMergeEpisode]
  ) async -> Date? {
    Self.log.trace(
      """
      applyParsedFeed
        podcast: \(podcast.toString)
        podcastFeed: \(podcastFeed.toString)
      """
    )

    let episodesByMediaURL = Dictionary(
      uniqueKeysWithValues: existingEpisodes.map { ($0.mediaURL, $0) }
    )
    let episodesByGUID = Dictionary(
      uniqueKeysWithValues: existingEpisodes.map { ($0.guid, $0) }
    )

    let newUnsavedPodcast: UnsavedPodcast
    do {
      newUnsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcast, feedURL: feedURL)
    } catch {
      Self.log.caughtError(
        """
        Failed to convert PodcastFeed to UnsavedPodcast
          Podcast: \(podcast.toString)
          PodcastFeed: \(podcastFeed.toString)
        """,
        error
      )
      return nil
    }
    let newPodcast = Podcast(
      id: podcast.id,
      creationDate: podcast.creationDate,
      from: newUnsavedPodcast
    )
    var unsavedEpisodes: [UnsavedEpisode] = []
    var updatedEpisodes: [FeedMergeEpisode] = []
    var embeddingWorkCreated = false

    for unsavedEpisode in podcastFeed.toUnsavedEpisodes(merging: existingEpisodes) {
      if let existingEpisode = episodesByMediaURL[unsavedEpisode.mediaURL]
        ?? episodesByGUID[unsavedEpisode.guid]
      {
        let updatedEpisode = FeedMergeEpisode(
          id: existingEpisode.id,
          from: unsavedEpisode
        )

        if !existingEpisode.rssEquals(updatedEpisode) {
          if existingEpisode.title != updatedEpisode.title
            || existingEpisode.description != updatedEpisode.description
          {
            embeddingWorkCreated = true
          }
          updatedEpisodes.append(updatedEpisode)
        }
      } else {
        embeddingWorkCreated = true
        unsavedEpisodes.append(unsavedEpisode)
      }
    }

    Self.log.log(
      level: unsavedEpisodes.isEmpty ? .trace : .debug,
      """
      applyParsedFeed: \(podcast.toString)
        \(unsavedEpisodes.count) new episodes
        \(updatedEpisodes.count) updated episodes
        New Episodes are:
        \(unsavedEpisodes.map { "    \($0.toString)" }.joined(separator: "\n"))
      """
    )

    let now = dateProvider.now
    let podcastToUpdate = podcast.rssEquals(newPodcast) ? nil : newPodcast
    if let podcastToUpdate,
      podcast.title != podcastToUpdate.title
        || podcast.description != podcastToUpdate.description
    {
      embeddingWorkCreated = true
    }
    let hasChanges =
      podcastToUpdate != nil || !unsavedEpisodes.isEmpty || !updatedEpisodes.isEmpty

    if !hasChanges {
      return now
    }

    let newEpisodes: [Episode]
    do {
      newEpisodes = try await repo.updateSeriesFromFeed(
        podcast: podcast,
        updatedPodcast: podcastToUpdate,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: updatedEpisodes
      )
    } catch {
      var description = podcast.toString
      if !updatedEpisodes.isEmpty {
        description +=
          "\nEpisodes:\n    \(updatedEpisodes.map { "[\($0.id)] - \($0.title)" }.joined(separator: "\n    "))"
      }
      if !unsavedEpisodes.isEmpty {
        description +=
          "\nUnsavedEpisodes:\n    \(unsavedEpisodes.map(\.toString).joined(separator: "\n    "))"
      }
      Self.log.caughtError(
        """
        Failed to update Podcast ID: \(podcast.id.rawValue)
          \(description)
        """,
        error
      )
      return nil
    }

    if embeddingWorkCreated {
      embeddingProcessor.workBecameAvailable()
    }

    if podcast.alwaysTranscribeNewEpisodes, !newEpisodes.isEmpty {
      let episodeIDs = newEpisodes.map(\.id)
      let transcriptionProcessor = transcriptionProcessor
      // Finish the durable queue handoff after the feed transaction commits,
      // even if the refresh caller is cancelled.
      await Task {
        do {
          try await transcriptionProcessor.enqueue(episodeIDs)
        } catch let error as TranscriptionQueueError {
          Self.log.caughtError(
            """
            applyParsedFeed: dropped automatic transcription for \
            \(episodeIDs.count) new episodes from podcast \(podcast.id)
            """,
            error,
            level: .notice
          )
        } catch {
          Self.log.caughtError(
            """
            applyParsedFeed: failed to enqueue automatic transcription for \
            \(episodeIDs.count) new episodes from podcast \(podcast.id)
            """,
            error
          )
        }
      }
      .value
    }

    if podcast.notifyNewEpisodes {
      await userNotificationManager.scheduleNewEpisodeNotification(
        podcast: podcast,
        episodes: newEpisodes  // Ignored if newEpisodes.isEmpty
      )
    }

    switch podcast.cacheAllEpisodes {
    case .never:
      break
    case .cache:
      for newEpisode in newEpisodes {
        do {
          try await cacheManager.downloadToCache(for: newEpisode.id)
        } catch {
          Self.log.caughtError(
            "applyParsedFeed: failed to cache episode \(newEpisode.id)",
            error
          )
        }
      }
    case .save:
      for newEpisode in newEpisodes {
        do {
          try await repo.updateSaveInCache(newEpisode.id, saveInCache: true)
        } catch {
          Self.log.caughtError(
            "applyParsedFeed: failed to set saveInCache for episode \(newEpisode.id)",
            error
          )
          continue
        }
        do {
          try await cacheManager.downloadToCache(for: newEpisode.id)
        } catch {
          Self.log.caughtError(
            "applyParsedFeed: failed to cache episode \(newEpisode.id)",
            error
          )
        }
      }
    }

    return now
  }
}
