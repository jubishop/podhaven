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
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.embeddingProcessor) private var embeddingProcessor
  @DynamicInjected(\.publisherTranscriptProcessor) private var publisherTranscriptProcessor
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.transcriptionProcessor) private var transcriptionProcessor

  private var userNotificationManager: UserNotificationManager {
    Container.shared.userNotificationManager()
  }

  private static let log = Log.as(LogSubsystem.Feed.refreshManager)

  private let downloadManager: DownloadManager
  private let inFlight = ThreadSafe<Set<URL>>([])
  // Feeds that fail to parse stay stale and retry every pass, so warn once per process.
  private let reportedUndecodableFeeds = ThreadSafe<Set<URL>>([])

  // MARK: - Initialization

  fileprivate init() {
    downloadManager = DownloadManager(
      session: Container.shared.podcastFeedSession(),
      maxConcurrentDownloads: 8
    )
  }

  // MARK: - Refresh Management

  func performRefresh(
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

    let stalePodcasts = try await repo.allPodcasts(
      Podcast.Columns.lastUpdate < Date.now.advanced(by: -stalenessThreshold.asTimeInterval)
        && filter,
      order: Podcast.Columns.lastUpdate.asc,
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
      let refreshes = collected.map { ($0.id, $0.lastUpdate, $0.feedValidators) }
      let urls = collected.map(\.url)
      // Task to execute even inside cancellation: ensures the timestamps
      // collected for series that already finished refreshing get flushed
      // before performRefresh returns, so the next cycle sees them as fresh.
      // inFlight URLs stay claimed until the flush commits (or fails) so a
      // racing refresh cannot re-fetch a series whose lastUpdate hasn't yet
      // hit the DB.
      await Task {
        defer { inFlight { state in for url in urls { state.remove(url) } } }
        do {
          try await repo.updateLastUpdates(refreshes)
        } catch {
          Self.log.caughtError(
            "performRefresh: failed to flush \(refreshes.count) lastUpdate timestamps",
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
      try await Task {
        try await repo.updateLastUpdates([
          (pending.id, pending.lastUpdate, pending.feedValidators)
        ])
      }
      .value
    }
    await publisherTranscriptProcessor.makeForegroundProgress()
  }

  // MARK: - Private Helpers

  private typealias PendingFlush = (
    id: Podcast.ID, lastUpdate: Date, url: URL, feedValidators: HTTPValidators?
  )

  // When a PendingFlush is returned, the caller owns removing url from
  // inFlight after the batched updateLastUpdates flush commits — otherwise a
  // racing refresh of the still-stale row could slip through the gap.
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
        lastUpdate: Date(),
        url: url,
        feedValidators: feedValidators
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
      return nil
    }

    let existingEpisodes = try await repo.feedMergeEpisodes(
      podcastID: podcast.id,
      matching: podcastFeed.episodeMediaGUIDs
    )

    guard
      let lastUpdate = await applyParsedFeed(
        podcast: podcast,
        podcastFeed: podcastFeed,
        existingEpisodes: existingEpisodes
      )
    else {
      return nil
    }
    releaseOnExit = false
    return PendingFlush(
      id: podcast.id,
      lastUpdate: lastUpdate,
      url: url,
      // Validators from the old URL don't describe the feed at its new one.
      feedValidators: podcastFeed.updatedFeedURL == podcast.feedURL ? downloadData.validators : nil
    )
  }

  private func applyParsedFeed(
    podcast: Podcast,
    podcastFeed: PodcastFeed,
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
      newUnsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcast)
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

    let now = Date()
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
