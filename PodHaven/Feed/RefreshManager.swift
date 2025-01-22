// Copyright Justin Bishop, 2025

import Factory
import Foundation

extension Container {
  var refreshManager: Factory<RefreshManager> {
    Factory(self) { RefreshManager() }.scope(.singleton)
  }
}

actor RefreshManager: Sendable {
  // MARK: - Static Helpers

  #if DEBUG
    static func initForTest(feedManager: FeedManager, repo: Repo) -> RefreshManager {
      RefreshManager(feedManager: feedManager, repo: repo)
    }
  #endif

  // MARK: - Initialization

  private let feedManager: FeedManager
  private let repo: Repo

  fileprivate init(
    feedManager: FeedManager = Container.shared.feedManager(),
    repo: Repo = Container.shared.repo()
  ) {
    self.feedManager = feedManager
    self.repo = repo
  }

  // MARK: - Refresh Management

  func refreshSeries(podcastSeries: PodcastSeries) async throws {
    let feedTask = await feedManager.addURL(podcastSeries.podcast.feedURL)
    let feedResult = await feedTask.feedParsed()
    switch feedResult {
    case .failure(let error):
      throw error
    case .success(let podcastFeed):
      var newPodcast = try podcastFeed.toPodcast(mergingExisting: podcastSeries.podcast)
      var unsavedEpisodes: [UnsavedEpisode] = []
      var existingEpisodes: [Episode] = []
      for feedItem in podcastFeed.episodes {
        if let existingEpisode = podcastSeries.episodes[id: feedItem.guid] {
          if let newExistingEpisode = try? feedItem.toEpisode(
            mergingExisting: existingEpisode
          ) {
            existingEpisodes.append(newExistingEpisode)
          }
        } else if let newUnsavedEpisode = try? feedItem.toUnsavedEpisode() {
          unsavedEpisodes.append(newUnsavedEpisode)
        }
      }
      newPodcast.lastUpdate = Date()
      try await repo.updateSeries(
        newPodcast,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: existingEpisodes
      )
    }
  }
}
