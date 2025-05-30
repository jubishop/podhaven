// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import UIKit

extension Container {
  var refreshManager: Factory<RefreshManager> {
    Factory(self) { RefreshManager() }.scope(.cached)
  }
}

actor RefreshManager {
  @LazyInjected(\.feedManager) private var feedManager
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.repo) private var repo

  // MARK: - State Management

  private var backgroundRefreshTask: Task<Void, Never>?
  private var activationTask: Task<Void, Never>?
  private var deactivationTask: Task<Void, Never>?

  // MARK: - Initialization

  fileprivate init() {}

  func start() async {
    if await UIApplication.shared.applicationState == .active {
      activated()
    }

    startListeningToActivation()
    startListeningToDeactivation()
  }

  // MARK: - Refresh Management

  func performRefresh(stalenessThreshold: Date, filter: SQLExpression = AppDB.NoOp)
    async throws(RefreshError)
  {
    try await RefreshError.catch {
      try await withThrowingDiscardingTaskGroup { group in
        let allStaleSubscribedPodcastSeries = try await repo.allPodcastSeries(
          Podcast.Columns.lastUpdate < stalenessThreshold && filter
        )
        for podcastSeries in allStaleSubscribedPodcastSeries {
          group.addTask {
            try? await self.refreshSeries(podcastSeries: podcastSeries)
          }
        }
      }
    }
  }

  func refreshSeries(podcastSeries: PodcastSeries) async throws(RefreshError) {
    let feedTask = await feedManager.addURL(podcastSeries.podcast.feedURL)
    let podcastFeed: PodcastFeed
    do {
      podcastFeed = try await feedTask.feedParsed()
    } catch {
      throw RefreshError.parseFailure(podcastSeries: podcastSeries, caught: error)
    }
    try await updateSeriesFromFeed(podcastSeries: podcastSeries, podcastFeed: podcastFeed)
  }

  func updateSeriesFromFeed(podcastSeries: PodcastSeries, podcastFeed: PodcastFeed)
    async throws(RefreshError)
  {
    try await RefreshError.catch {
      let newUnsavedPodcast = try podcastFeed.toUnsavedPodcast(
        merging: podcastSeries.podcast.unsaved
      )
      var newPodcast = Podcast(id: podcastSeries.id, from: newUnsavedPodcast)
      var unsavedEpisodes: [UnsavedEpisode] = []
      var existingEpisodes: [Episode] = []
      for feedItem in podcastFeed.episodes {
        if let existingEpisode = podcastSeries.episodes[id: feedItem.guid] {
          if let newUnsavedExistingEpisode = try? feedItem.toUnsavedEpisode(
            merging: existingEpisode
          ) {
            existingEpisodes.append(
              Episode(id: existingEpisode.id, from: newUnsavedExistingEpisode)
            )
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

  // MARK: - Private Helpers

  private func activated() {
    backgroundRefreshTask?.cancel()
    backgroundRefreshTask = Task(priority: .utility) {
      while !Task.isCancelled {
        try? await self.performRefresh(
          stalenessThreshold: 10.minutesAgo,
          filter: Podcast.subscribed
        )
        try? await Task.sleep(for: .minutes(15))
      }
    }
  }

  private func backgrounded() {
    backgroundRefreshTask?.cancel()
    backgroundRefreshTask = nil
  }

  private func startListeningToActivation() {
    Assert.precondition(
      self.activationTask == nil,
      "activationTask already exists?"
    )

    self.activationTask = Task {
      for await _ in notifications(UIApplication.didBecomeActiveNotification) {
        activated()
      }
    }
  }

  private func startListeningToDeactivation() {
    Assert.precondition(
      self.deactivationTask == nil,
      "deactivationTask already exists?"
    )

    self.deactivationTask = Task {
      for await _ in notifications(UIApplication.willResignActiveNotification) {
        backgrounded()
      }
    }
  }
}
