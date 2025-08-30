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
  @DynamicInjected(\.repo) private var uiRepo
  @DynamicInjected(\.backgroundRepo) private var backgroundRepo
  @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.Feed.refreshManager)

  enum RefreshPriority {
    case ui
    case background
  }

  // MARK: - State Management

  private var backgroundRefreshTask: Task<Void, Never>?
  private var activeRefreshTask: Task<Void, any Error>?

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

  func performRefresh(
    stalenessThreshold: Date,
    filter: SQLExpression = AppDB.NoOp,
    priority: RefreshPriority = .ui
  ) async throws(RefreshError) {
    Self.log.debug(
      """
      performRefresh:
        stalenessThreshold: \(stalenessThreshold)
        filter: \(filter)
        priority: \(priority)
      """
    )

    let repo = priority == .ui ? uiRepo : backgroundRepo
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
              try await refreshSeries(podcastSeries: podcastSeries, priority: priority)
            } catch {
              Self.log.error(error, mundane: .trace)
            }
          }
        }
      }
    }

    Self.log.trace("performRefresh: completed")
  }

  @discardableResult
  func refreshSeries(podcastSeries: PodcastSeries, priority: RefreshPriority = .ui)
    async throws(RefreshError) -> Bool
  {
    Self.log.trace(
      """
      refreshSeries: 
        podcastSeries: \(podcastSeries.toString)
        priority: \(priority)
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
      podcastFeed: podcastFeed,
      priority: priority
    )
    return true
  }

  func updateSeriesFromFeed(
    podcastSeries: PodcastSeries,
    podcastFeed: PodcastFeed,
    priority: RefreshPriority = .ui
  ) async throws(RefreshError) {
    Self.log.trace(
      """
      updateSeriesFromFeed
        podcastSeries: \(podcastSeries.toString)
        podcastFeed: \(podcastFeed.toString)
        priority: \(priority)
      """
    )

    let episodesByMedia = IdentifiedArray(
      uniqueElements: podcastSeries.episodes,
      id: \.media
    )

    let repo = priority == .ui ? uiRepo : backgroundRepo
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
          ?? episodesByMedia[id: feedItem.media]
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

        // Only bother notifying for significant changes
        if priority == .background {
          await notifyUIOfDatabaseChanges(podcastID: podcastSeries.id)
        }
      } else {
        try await repo.updateLastUpdate(podcastSeries.id)
      }
    }
  }

  // MARK: - Database Bridge

  private func notifyUIOfDatabaseChanges(podcastID: Podcast.ID) async {
    do {
      try await uiRepo.notifyChanges(for: podcastID)
      Self.log.trace("Notified UI database of changes for podcast \(podcastID)")
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Private Helpers

  private func activated() {
    Self.log.trace("activated: starting background refresh task")

    cancelRefreshTasks()
    backgroundRefreshTask = Task(priority: .background) { [weak self] in
      guard let self else { return }

      while !Task.isCancelled {
        let refreshTask = Task {
          Self.log.debug("backgroundRefreshTask: performing refresh")
          try await self.performRefresh(
            stalenessThreshold: 10.minutesAgo,
            filter: Podcast.subscribed,
            priority: .background
          )
        }

        await self.setActiveRefreshTask(refreshTask)
        do {
          try await refreshTask.value
        } catch {
          Self.log.error(error)
        }
        await self.setActiveRefreshTask(nil)

        try? await self.sleeper.sleep(for: .minutes(15))
      }
    }
  }

  private func backgrounded() async {
    Self.log.trace("backgrounded: waiting for active refresh to complete")

    if let activeRefreshTask {
      Self.log.debug("backgrounded: waiting for active refresh task to complete")
      do {
        try await activeRefreshTask.value
        Self.log.debug("backgrounded: active refresh completed gracefully")
      } catch {
        Self.log.error(error)
      }
    }

    Self.log.debug("backgrounded: cancelling background refresh task")
    cancelRefreshTasks()
  }

  private func cancelRefreshTasks() {
    activeRefreshTask?.cancel()
    activeRefreshTask = nil
    backgroundRefreshTask?.cancel()
    backgroundRefreshTask = nil
  }

  private func setActiveRefreshTask(_ task: Task<Void, any Error>?) async {
    activeRefreshTask = task
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
