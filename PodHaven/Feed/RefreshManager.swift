// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import UIKit

extension Container {
  var refreshManager: Factory<RefreshManager> {
    Factory(self) { RefreshManager() }.scope(.cached)
  }
}

actor RefreshManager {
  @LazyInjected(\.feedManager) var feedManager
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.Feed.refreshManager)

  // MARK: - State Management

  private var backgroundRefreshTask: Task<Void, Never>?

  // MARK: - Initialization

  fileprivate init() {}

  func start() async {
    Self.log.debug("start: executing")

    if await UIApplication.shared.applicationState == .active {
      Self.log.trace("start: app already active, activating refresh task")
      activated()
    } else {
      Self.log.trace("start: app not active, waiting for activation")
    }

    startListeningToActivation()
    startListeningToDeactivation()
  }

  // MARK: - Refresh Management

  func performRefresh(stalenessThreshold: Date, filter: SQLExpression = AppDB.NoOp)
    async throws(RefreshError)
  {
    Self.log.debug(
      """
      performRefresh:
        stalenessThreshold: \(stalenessThreshold)
        filter: \(filter)
      """
    )

    try await RefreshError.catch {
      try await withThrowingDiscardingTaskGroup { group in
        let allStaleSubscribedPodcastSeries = try await repo.allPodcastSeries(
          Podcast.Columns.lastUpdate < stalenessThreshold && filter
        )
        Self.log.debug(
          "performRefresh: found \(allStaleSubscribedPodcastSeries.count) stale series"
        )

        for podcastSeries in allStaleSubscribedPodcastSeries {
          group.addTask { [weak self] in
            guard let self else { return }
            do {
              try await refreshSeries(podcastSeries: podcastSeries)
            } catch {
              Self.log.error(error, mundane: .trace)
            }
          }
        }
      }
    }

    Self.log.debug("Perform refresh completed")
  }

  @discardableResult
  func refreshSeries(podcastSeries: PodcastSeries) async throws(RefreshError) -> Bool {
    Self.log.trace("refreshSeries: \(podcastSeries.toString)")

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
    try await updateSeriesFromFeed(podcastSeries: podcastSeries, podcastFeed: podcastFeed)
    return true
  }

  func updateSeriesFromFeed(podcastSeries: PodcastSeries, podcastFeed: PodcastFeed)
    async throws(RefreshError)
  {
    Self.log.trace(
      """
      updateSeriesFromFeed
        podcastSeries: \(podcastSeries.toString)
        podcastFeed: \(podcastFeed.toString)
      """
    )

    let episodesByMedia = IdentifiedArray(
      uniqueElements: podcastSeries.episodes,
      id: \.media
    )

    try await RefreshError.catch {
      let newUnsavedPodcast = try podcastFeed.toUnsavedPodcast(
        merging: podcastSeries.podcast.unsaved
      )
      let newPodcast = Podcast(id: podcastSeries.id, from: newUnsavedPodcast)
      var unsavedEpisodes: [UnsavedEpisode] = []
      var updatedEpisodes: [Episode] = []

      for feedItem in podcastFeed.episodes {
        if let existingEpisode = podcastSeries.episodes[id: feedItem.guid]
          ?? episodesByMedia[id: feedItem.media]
        {
          do {
            let updatedEpisode = Episode(
              id: existingEpisode.id,
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

  // MARK: - Private Helpers

  private func activated() {
    Self.log.trace("activated: starting background refresh task")

    backgroundRefreshTask?.cancel()
    backgroundRefreshTask = Task(priority: .background) { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        Self.log.debug("activated: performing refresh check")
        do {
          try await performRefresh(
            stalenessThreshold: 10.minutesAgo,
            filter: Podcast.subscribed
          )
        } catch {
          Self.log.error(error)
        }

        try? await sleeper.sleep(for: .minutes(15))
      }
    }
  }

  private func backgrounded() {
    Self.log.trace("backgrounded: cancelling refresh task")

    backgroundRefreshTask?.cancel()
    backgroundRefreshTask = nil
  }

  private func startListeningToActivation() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await _ in await notifications(UIApplication.didBecomeActiveNotification) {
        await activated()
      }
    }
  }

  private func startListeningToDeactivation() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await _ in await notifications(UIApplication.willResignActiveNotification) {
        await backgrounded()
      }
    }
  }
}
