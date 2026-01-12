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

  // MARK: - Initialization

  fileprivate init() {
    downloadManager = DownloadManager(session: Container.shared.podcastFeedSession())
  }

  // MARK: - Refresh Management

  func performRefresh(
    stalenessThreshold: Duration,
    filter: SQLExpression = AppDB.NoOp,
    limit: Int = Int.max
  ) async throws(RefreshError) {
    Self.log.debug(
      """
      performRefresh:
        stalenessThreshold: \(stalenessThreshold)
      """
    )

    try await RefreshError.catch {
      try await withThrowingDiscardingTaskGroup { group in
        let staleSeries = try await repo.allPodcastSeries(
          Podcast.Columns.lastUpdate < Date.now.advanced(by: -stalenessThreshold.asTimeInterval)
            && filter,
          order: Podcast.Columns.lastUpdate.asc,
          limit: limit,
        )
        Self.log.debug(
          "performRefresh: fetched \(staleSeries.count) stale series (limit: \(limit))"
        )

        for podcastSeries in staleSeries {
          group.addTask { [podcastSeries] in
            do {
              try await refreshSeries(podcastSeries: podcastSeries)
            } catch {
              Self.log.error(error, mundane: .trace)
            }
          }
        }
      }
    }

    Self.log.debug("performRefresh: completed")
  }

  @discardableResult
  func refreshSeries(podcastSeries: PodcastSeries)
    async throws(RefreshError) -> Bool
  {
    Self.log.trace(
      """
      refreshSeries: 
        podcastSeries: \(podcastSeries.toString)
      """
    )

    if await downloadManager.hasURL(podcastSeries.podcast.feedURL.rawValue) {
      Self.log.debug("refreshSeries: URL for \(podcastSeries.toString) already being fetched")
      return false
    }

    let downloadTask = await downloadManager.addURL(podcastSeries.podcast.feedURL.rawValue)
    let podcastFeed: PodcastFeed
    do {
      podcastFeed = try await PodcastFeed.parse(downloadTask.downloadFinished())
    } catch {
      throw RefreshError.parseFailure(podcastSeries: podcastSeries, caught: error)
    }

    try await updateSeriesFromFeed(
      podcastSeries: podcastSeries,
      podcastFeed: podcastFeed
    )

    return true
  }

  func updateSeriesFromFeed(
    podcastSeries: PodcastSeries,
    podcastFeed: PodcastFeed
  ) async throws(RefreshError) {
    Self.log.trace(
      """
      updateSeriesFromFeed
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

    try await RefreshError.catch {
      let newUnsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries.podcast)
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
        updateSeriesFromFeed: \(podcastSeries.toString)
          \(unsavedEpisodes.count) new episodes
          \(updatedEpisodes.count) updated episodes 
          New Episodes are: 
          \(unsavedEpisodes.map { "    \($0.toString)" }.joined(separator: "\n"))
        """
      )

      let podcastToUpdate = podcastSeries.podcast.rssEquals(newPodcast) ? nil : newPodcast
      if podcastToUpdate != nil || !unsavedEpisodes.isEmpty || !updatedEpisodes.isEmpty {
        let newEpisodes = try await repo.updateSeriesFromFeed(
          podcastSeries: podcastSeries,
          podcast: podcastToUpdate,
          unsavedEpisodes: unsavedEpisodes,
          existingEpisodes: updatedEpisodes
        )

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
              Self.log.error(error)
            }
          }
        case .save:
          for newEpisode in newEpisodes {
            do {
              try await repo.updateSaveInCache(newEpisode.id, saveInCache: true)
              try await cacheManager.downloadToCache(for: newEpisode.id)
            } catch {
              Self.log.error(error)
            }
          }
        }
      }

      try await repo.updateLastUpdate(podcastSeries.id)
    }
  }
}
