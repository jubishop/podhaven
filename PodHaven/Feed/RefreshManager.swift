// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
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

  func performRefresh(
    stalenessThreshold: Date,
    filter: SendableSQLSpecificExpressible = AppDB.nullFilter
  )
    async throws
  {
    try await withThrowingDiscardingTaskGroup { group in
      let allStaleSubscribedPodcastSeries: PodcastSeriesArray = try await repo.allPodcastSeries(
        Schema.lastUpdateColumn < stalenessThreshold && filter
      )
      for podcastSeries in allStaleSubscribedPodcastSeries {
        group.addTask {
          try await self.refreshSeries(podcastSeries: podcastSeries)
        }
      }
    }
  }

  func refreshSeries(podcastSeries: PodcastSeries) async throws {
    let feedTask = await feedManager.addURL(podcastSeries.podcast.feedURL)
    let feedResult = await feedTask.feedParsed()
    switch feedResult {
    case .failure(let error):
      throw error
    case .success(let podcastFeed):
      try await updateSeriesFromFeed(podcastSeries: podcastSeries, podcastFeed: podcastFeed)
    }
  }

  func updateSeriesFromFeed(podcastSeries: PodcastSeries, podcastFeed: PodcastFeed) async throws {
    let newUnsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries.podcast.unsaved)
    var newPodcast = Podcast(id: podcastSeries.id, from: newUnsavedPodcast)
    var unsavedEpisodes: [UnsavedEpisode] = []
    var existingEpisodes: [Episode] = []
    for feedItem in podcastFeed.episodes {
      if let existingEpisode = podcastSeries.episodes[id: feedItem.guid] {
        if let newUnsavedExistingEpisode = try? feedItem.toUnsavedEpisode(merging: existingEpisode)
        {
          existingEpisodes.append(Episode(id: existingEpisode.id, from: newUnsavedExistingEpisode))
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

  // MARK: - Private Helpers

  private func activated() {
    backgroundRefreshTask = Task(priority: .background) { [unowned self] in
      while !Task.isCancelled {
        try? await performRefresh(
          stalenessThreshold: 10.minutesAgo,
          filter: Schema.subscribedColumn == true
        )
        try? await Task.sleep(for: .minutes(15))
      }
    }
  }

  private func backgrounded() {
    backgroundRefreshTask?.cancel()
    backgroundRefreshTask = nil
  }
}
