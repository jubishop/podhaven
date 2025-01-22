// Copyright Justin Bishop, 2025

import Factory
import Foundation
import UIKit

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

  // MARK: - State Management

  private var backgroundRefreshTask: Task<Void, Never>?

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

  // MARK: - Background Refreshing

  func startBackgroundRefreshing() async {
    if await UIApplication.shared.applicationState == .active {
      activated()
    }

    Task(priority: .utility) { [unowned self] in
      for await _ in NotificationCenter.default.notifications(
        named: UIApplication.didBecomeActiveNotification
      ) {
        self.activated()
      }
    }

    Task(priority: .utility) { [unowned self] in
      for await _ in NotificationCenter.default.notifications(
        named: UIApplication.willResignActiveNotification
      ) {
        self.backgrounded()
      }
    }
  }

  private func activated() {
    backgroundRefreshTask = Task(priority: .background) { [unowned self] in
      while !Task.isCancelled {
        try? await performScheduledRefresh()
        try? await Task.sleep(for: .seconds(900)) // 15 minutes
      }
    }
  }

  private func backgrounded() {
    backgroundRefreshTask?.cancel()
    backgroundRefreshTask = nil
  }

  private func performScheduledRefresh() async throws {
    try await withThrowingDiscardingTaskGroup { group in
      for podcastSeries in try await repo.allStalePodcastSeries() {
        group.addTask {
          try await self.refreshSeries(podcastSeries: podcastSeries)
        }
      }
    }
  }
}
