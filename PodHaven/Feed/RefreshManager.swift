// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
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
    filter: SQLExpression = AppDB.NoOp,
    limit: Int = Int.max
  ) async throws {
    Self.log.debug(
      """
      performRefresh:
        stalenessThreshold: \(stalenessThreshold)
      """
    )

    let staleSeries = try await repo.allPodcastSeries(
      Podcast.Columns.lastUpdate < Date.now.advanced(by: -stalenessThreshold.asTimeInterval)
        && filter,
      order: Podcast.Columns.lastUpdate.asc,
      limit: limit
    )
    Self.log.debug(
      "performRefresh: fetched \(staleSeries.count) stale series (limit: \(limit))"
    )

    let collected = await withTaskGroup(
      of: (Podcast.ID, Date)?.self,
      returning: [(Podcast.ID, Date)].self
    ) { group in
      for podcastSeries in staleSeries {
        group.addTask { [podcastSeries] in
          do {
            return try await performRefreshCycle(podcastSeries: podcastSeries)
          } catch {
            Self.log.caughtError(
              "Failed to refresh series: \(podcastSeries.toString)",
              error,
              level: { _ in .info }
            )
            return nil
          }
        }
      }
      var results = [(Podcast.ID, Date)](capacity: staleSeries.count)
      for await result in group {
        if let result {
          results.append(result)
        }
      }
      return results
    }

    if !collected.isEmpty {
      // Task to execute even inside cancellation: ensures the timestamps
      // collected for series that already finished refreshing get flushed
      // before performRefresh returns, so the next cycle sees them as fresh.
      await Task {
        do {
          try await repo.updateLastUpdates(collected)
        } catch {
          Self.log.caughtError(
            "performRefresh: failed to flush \(collected.count) lastUpdate timestamps",
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

    if let pending = try await performRefreshCycle(podcastSeries: podcastSeries) {
      try await repo.updateLastUpdates([pending])
    }
  }

  // MARK: - Private Helpers

  // Fetches + parses the feed, then either writes everything (including
  // lastUpdate) inline via repo.updateSeriesFromFeed when the feed had real
  // changes, or returns the (id, Date) pair the caller should flush via
  // repo.updateLastUpdates when the feed was unchanged. Returns nil when the
  // work was deduped via inFlight or failed before any write could happen.
  // inFlight is held for the full cycle (download + parse + write), so a
  // concurrent caller for the same feed silently no-ops until the in-flight
  // cycle completes.
  private func performRefreshCycle(
    podcastSeries: PodcastSeries
  ) async throws -> (Podcast.ID, Date)? {
    let url = podcastSeries.podcast.feedURL.rawValue

    let alreadyInFlight = inFlight { !$0.insert(url).inserted }
    if alreadyInFlight {
      Self.log.debug(
        "performRefreshCycle: \(podcastSeries.toString) already in-flight; skipping"
      )
      return nil
    }
    defer { inFlight { $0.remove(url) } }

    let downloadTask = await downloadManager.addURL(url)
    let podcastFeed: PodcastFeed
    do {
      podcastFeed = try await PodcastFeed.parse(downloadTask.downloadFinished())
    } catch {
      Self.log.caughtError(
        """
        Failed to parse podcast feed
          PodcastSeries: \(podcastSeries.toString)
          FeedURL: \(podcastSeries.podcast.feedURL)
        """,
        error,
        level: { _ in .notice }
      )
      return nil
    }

    return await applyParsedFeed(
      podcastSeries: podcastSeries,
      podcastFeed: podcastFeed
    )
  }

  private func applyParsedFeed(
    podcastSeries: PodcastSeries,
    podcastFeed: PodcastFeed
  ) async -> (Podcast.ID, Date)? {
    Self.log.trace(
      """
      applyParsedFeed
        podcastSeries: \(podcastSeries.toString)
        podcastFeed: \(podcastFeed.toString)
      """
    )

    let episodesByMediaURL = IdentifiedArray(
      uniqueElements: podcastSeries.episodes,
      id: \.mediaURL
    )
    let episodesByGUID = IdentifiedArray(
      uniqueElements: podcastSeries.episodes,
      id: \.guid
    )

    let newUnsavedPodcast: UnsavedPodcast
    do {
      newUnsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries.podcast)
    } catch {
      Self.log.caughtError(
        """
        Failed to convert PodcastFeed to UnsavedPodcast
          PodcastSeries: \(podcastSeries.toString)
          PodcastFeed: \(podcastFeed.toString)
        """,
        error
      )
      return nil
    }
    let newPodcast = Podcast(
      id: podcastSeries.id,
      creationDate: podcastSeries.podcast.creationDate,
      from: newUnsavedPodcast
    )
    var unsavedEpisodes: [UnsavedEpisode] = []
    var updatedEpisodes: [Episode] = []

    for unsavedEpisode in podcastFeed.toUnsavedEpisodes(merging: podcastSeries.episodes) {
      if let existingEpisode = episodesByMediaURL[id: unsavedEpisode.mediaURL]
        ?? episodesByGUID[id: unsavedEpisode.guid]
      {
        let updatedEpisode = Episode(
          id: existingEpisode.id,
          creationDate: existingEpisode.creationDate,
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
      applyParsedFeed: \(podcastSeries.toString)
        \(unsavedEpisodes.count) new episodes
        \(updatedEpisodes.count) updated episodes
        New Episodes are:
        \(unsavedEpisodes.map { "    \($0.toString)" }.joined(separator: "\n"))
      """
    )

    let now = Date()
    let podcastToUpdate = podcastSeries.podcast.rssEquals(newPodcast) ? nil : newPodcast
    let hasChanges =
      podcastToUpdate != nil || !unsavedEpisodes.isEmpty || !updatedEpisodes.isEmpty

    if !hasChanges {
      return (podcastSeries.id, now)
    }

    let newEpisodes: [Episode]
    do {
      newEpisodes = try await repo.updateSeriesFromFeed(
        podcastSeries: podcastSeries,
        podcast: podcastToUpdate,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: updatedEpisodes
      )
    } catch {
      var description = podcastSeries.toString
      if !updatedEpisodes.isEmpty {
        description +=
          "\nEpisodes:\n    \(updatedEpisodes.map(\.toString).joined(separator: "\n    "))"
      }
      if !unsavedEpisodes.isEmpty {
        description +=
          "\nUnsavedEpisodes:\n    \(unsavedEpisodes.map(\.toString).joined(separator: "\n    "))"
      }
      Self.log.caughtError(
        """
        Failed to update PodcastSeries ID: \(podcastSeries.id.rawValue)
          \(description)
        """,
        error
      )
      return nil
    }

    if podcastSeries.podcast.notifyNewEpisodes {
      await userNotificationManager.scheduleNewEpisodeNotification(
        podcast: podcastSeries.podcast,
        episodes: newEpisodes  // Ignored if newEpisodes.isEmpty
      )
    }

    switch podcastSeries.podcast.cacheAllEpisodes {
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
