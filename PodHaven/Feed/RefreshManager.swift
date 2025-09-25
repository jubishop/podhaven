// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging

extension Container {
  var refreshManager: Factory<RefreshManager> {
    Factory(self) { RefreshManager() }.scope(.cached)
  }
}

struct RefreshManager {
  @DynamicInjected(\.feedManager) private var feedManager
  @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.Feed.refreshManager)

  // MARK: - Initialization

  fileprivate init() {}

  // MARK: - Refresh Management

  func performRefresh(
    stalenessThreshold: Date = 1.hoursAgo,
    filter: SQLExpression = AppDB.NoOp,
    limit: Int = Int.max
  ) async throws(RefreshError) {
    Self.log.debug(
      """
      performRefresh:
        stalenessThreshold: \(stalenessThreshold)
        filter: \(filter)
      """
    )

    try await RefreshError.catch {
      try await withThrowingDiscardingTaskGroup { group in
        let staleSeries = try await repo.allPodcastSeries(
          Podcast.Columns.lastUpdate < stalenessThreshold && filter,
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

    if await feedManager.hasURL(podcastSeries.podcast.feedURL) {
      Self.log.debug("refreshSeries: URL for \(podcastSeries.toString) already being fetched")
      return false
    }

    let feedTask = await feedManager.addURL(podcastSeries.podcast.feedURL)
    let podcastFeed: PodcastFeed
    do {
      podcastFeed = try await feedTask.feedParsed()
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
      let newUnsavedPodcast = try podcastFeed.toUnsavedPodcast(
        merging: podcastSeries.podcast.unsaved
      )
      let newPodcast = Podcast(
        id: podcastSeries.id,
        creationDate: podcastSeries.podcast.creationDate,
        from: newUnsavedPodcast
      )
      var unsavedEpisodes: [UnsavedEpisode] = []
      var updatedEpisodes: [Episode] = []

      for feedItem in podcastFeed.episodes {
        if let existingEpisode = podcastSeries.episodes[id: feedItem.mediaGUID]
          ?? episodesByMediaURL[id: feedItem.mediaURL]
          ?? episodesByGUID[id: feedItem.guid]
        {
          do {
            let updatedEpisode = Episode(
              id: existingEpisode.id,
              creationDate: existingEpisode.creationDate,
              from: try feedItem.toUnsavedEpisode(merging: existingEpisode)
            )

            if !existingEpisode.rssEquals(updatedEpisode) {
              updatedEpisodes.append(updatedEpisode)
            }
          } catch {
            Self.log.error(error)
          }
        } else {
          do {
            unsavedEpisodes.append(try feedItem.toUnsavedEpisode())
          } catch {
            Self.log.error(error)
          }
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

      var podcastToUpdate = podcastSeries.podcast.rssEquals(newPodcast) ? nil : newPodcast
      podcastToUpdate?.lastUpdate = Date()

      if podcastToUpdate != nil || !unsavedEpisodes.isEmpty || !updatedEpisodes.isEmpty {
        try await repo.updateSeriesFromFeed(
          podcastID: podcastSeries.id,
          podcast: podcastToUpdate,
          unsavedEpisodes: unsavedEpisodes,
          existingEpisodes: updatedEpisodes
        )
      } else {
        try await repo.updateLastUpdate(podcastSeries.id)
      }
    }
  }
}
