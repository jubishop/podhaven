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
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var userNotificationManager: UserNotificationManager {
    Container.shared.userNotificationManager()
  }

  private static let log = Log.as(LogSubsystem.Feed.refreshManager)

  private let downloadManager: DownloadManager
  private let inFlight = ThreadSafe<Set<URL>>([])

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
      let pairs = collected.map { ($0.id, $0.lastUpdate) }
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
          try await repo.updateLastUpdates(pairs)
        } catch {
          Self.log.caughtError(
            "performRefresh: failed to flush \(pairs.count) lastUpdate timestamps",
            error
          )
        }
      }
      .value
    }

    Self.log.debug("performRefresh: completed")
  }

  func refreshSeries(podcastSeries: PodcastSeries) async throws {
    Self.log.trace(
      """
      refreshSeries:
        podcastSeries: \(podcastSeries.toString)
      """
    )

    guard let pending = try await performRefreshCycle(podcast: podcastSeries.podcast)
    else { return }

    defer { inFlight { $0.remove(pending.url) } }
    try await repo.updateLastUpdates([(pending.id, pending.lastUpdate)])
  }

  // MARK: - Private Helpers

  private typealias PendingFlush = (id: Podcast.ID, lastUpdate: Date, url: URL)

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

    let downloadTask = await downloadManager.addURL(url)
    let podcastFeed: PodcastFeed
    do {
      podcastFeed = try await PodcastFeed.parse(downloadTask.downloadFinished())
    } catch {
      Self.log.caughtError(
        """
        Failed to parse podcast feed
          Podcast: \(podcast.toString)
          FeedURL: \(podcast.feedURL)
        """,
        error,
        level: .notice
      )
      return nil
    }

    let existingEpisodes = try await repo.feedMergeEpisodes(
      podcastID: podcast.id,
      matching: podcastFeed.episodeMediaGUIDs
    )

    guard
      let pending = await applyParsedFeed(
        podcast: podcast,
        podcastFeed: podcastFeed,
        existingEpisodes: existingEpisodes
      )
    else {
      return nil
    }
    releaseOnExit = false
    return PendingFlush(id: pending.id, lastUpdate: pending.lastUpdate, url: url)
  }

  private func applyParsedFeed(
    podcast: Podcast,
    podcastFeed: PodcastFeed,
    existingEpisodes: [FeedMergeEpisode]
  ) async -> (id: Podcast.ID, lastUpdate: Date)? {
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

    for unsavedEpisode in podcastFeed.toUnsavedEpisodes(merging: existingEpisodes) {
      if let existingEpisode = episodesByMediaURL[unsavedEpisode.mediaURL]
        ?? episodesByGUID[unsavedEpisode.guid]
      {
        let updatedEpisode = FeedMergeEpisode(
          id: existingEpisode.id,
          from: unsavedEpisode
        )

        if !existingEpisode.rssEquals(updatedEpisode) {
          updatedEpisodes.append(updatedEpisode)
        }
      } else {
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
    let hasChanges =
      podcastToUpdate != nil || !unsavedEpisodes.isEmpty || !updatedEpisodes.isEmpty

    if !hasChanges {
      return (podcast.id, now)
    }

    let newEpisodes: [Episode]
    do {
      newEpisodes = try await repo.updateSeriesFromFeed(
        podcastSeries: PodcastSeries(podcast: podcast),
        podcast: podcastToUpdate,
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

    return nil
  }
}
