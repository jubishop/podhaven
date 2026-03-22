// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

@MainActor protocol SelectableEpisodeList: AnyObject {
  associatedtype EpisodeType: EpisodeListable & Searchable

  var episodeList: PowerList<EpisodeType> { get }

  var selectedEpisodes: [EpisodeType] { get }
  var selectedSavedEpisodeIDs: [Episode.ID] { get }
  var selectedPodcastEpisodeIDs: [Episode.ID] { get async throws }

  // Must Implement: Saves new PodcastEpisodes as needed
  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws }

  var anySelectedQueued: Bool { get }
  var anySelectedNotAtTopOfQueue: Bool { get }
  var anySelectedNotAtBottomOfQueue: Bool { get }
  var anySelectedNotQueued: Bool { get }
  var anySelectedNotCached: Bool { get }
  var anySelectedNotSavedInCache: Bool { get }
  var anySelectedSavedInCache: Bool { get }
  var anySelectedCanClearCache: Bool { get }
  var anySelectedCanStopCaching: Bool { get }
  var anySelectedUnfinished: Bool { get }

  func playSelectedEpisodes()
  func addSelectedEpisodesToTopOfQueue()
  func addSelectedEpisodesToBottomOfQueue()
  func replaceQueueWithSelected()
  func dequeueSelectedEpisodes()
  func cacheSelectedEpisodes()
  func uncacheSelectedEpisodes()
  func unsaveSelectedEpisodesFromCache()
  func cancelSelectedEpisodeDownloads()
  func markSelectedEpisodesFinished()
}

extension SelectableEpisodeList {
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var playManager: PlayManager { Container.shared.playManager() }
  private var queue: any Queueing { Container.shared.queue() }
  private var repo: any Databasing { Container.shared.repo() }
  private var sharedState: SharedState { Container.shared.sharedState() }

  nonisolated private static var log: Logger { Log.as(LogSubsystem.ViewProtocols.episodeList) }

  // MARK: - Selection Getters

  var selectedEpisodes: [EpisodeType] { episodeList.selectedEntries.elements }
  var selectedSavedEpisodeIDs: [Episode.ID] {
    selectedEpisodes.compactMap(\.episodeID)
  }
  var selectedPodcastEpisodeIDs: [Episode.ID] {
    get async throws {
      try await selectedPodcastEpisodes.map(\.id)
    }
  }

  // MARK: - "Any"? Getters

  var anySelectedQueued: Bool {
    selectedEpisodes.contains { $0.queued }
  }

  var anySelectedNotQueued: Bool {
    selectedEpisodes.contains { !$0.queued }
  }

  var anySelectedNotAtTopOfQueue: Bool {
    selectedEpisodes.contains { !($0.queueOrder == 0) }
  }

  var anySelectedNotAtBottomOfQueue: Bool {
    selectedEpisodes.contains { $0.queueOrder != sharedState.maxQueuePosition }
  }

  var anySelectedNotCached: Bool {
    selectedEpisodes.contains { $0.cacheStatus != .cached }
  }

  var anySelectedNotSavedInCache: Bool {
    selectedEpisodes.contains { $0.cacheStatus != .cached && !$0.saveInCache }
  }

  var anySelectedSavedInCache: Bool {
    selectedEpisodes.contains { $0.saveInCache }
  }

  var anySelectedCanClearCache: Bool {
    selectedEpisodes.contains { $0.cacheStatus == .cached && CacheManager.canClearCache($0) }
  }

  var anySelectedCanStopCaching: Bool {
    selectedEpisodes.contains { $0.cacheStatus == .caching && CacheManager.canClearCache($0) }
  }

  var anySelectedUnfinished: Bool {
    selectedEpisodes.contains { !$0.finished }
  }

  // MARK: - Actions

  func addSelectedEpisodesToBottomOfQueue() {
    guard !selectedEpisodes.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeIDs = try await selectedPodcastEpisodeIDs
        try await queue.append(episodeIDs)
      } catch {
        Self.log.caughtError("addSelectedEpisodesToBottomOfQueue: failed", error)
      }
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    guard !selectedEpisodes.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeIDs = try await selectedPodcastEpisodeIDs
        try await queue.unshift(episodeIDs)
      } catch {
        Self.log.caughtError("addSelectedEpisodesToTopOfQueue: failed", error)
      }
    }
  }

  func replaceQueueWithSelected() {
    guard !selectedEpisodes.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeIDs = try await selectedPodcastEpisodeIDs
        try await queue.replace(episodeIDs)
      } catch {
        Self.log.caughtError("replaceQueueWithSelected: failed", error)
      }
    }
  }

  func playSelectedEpisodes() {
    guard !selectedEpisodes.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisodes = try await selectedPodcastEpisodes
        let firstPodcastEpisode = podcastEpisodes.first
        let allExceptFirstPodcastEpisode = podcastEpisodes.dropFirst()
        try await queue.unshift(allExceptFirstPodcastEpisode.map(\.id))
        if let firstPodcastEpisode {
          try await playManager.load(firstPodcastEpisode)
          await playManager.play()
        }
      } catch {
        Self.log.caughtError(
          "playSelectedEpisodes: failed to play \(selectedEpisodes.count) episodes",
          error
        )
      }
    }
  }

  func dequeueSelectedEpisodes() {
    let savedEpisodeIDs = selectedSavedEpisodeIDs
    guard !savedEpisodeIDs.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await queue.dequeue(savedEpisodeIDs)
      } catch {
        Self.log.caughtError(
          "dequeueSelectedEpisodes: failed to dequeue \(savedEpisodeIDs.count) episodes",
          error
        )
      }
    }
  }

  func cacheSelectedEpisodes() {
    guard anySelectedNotCached else { return }

    let log = Self.log
    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeIDs = try await selectedPodcastEpisodeIDs
        await withDiscardingTaskGroup { group in
          for episodeID in episodeIDs {
            group.addTask {
              do {
                try await Container.shared.cacheManager().downloadToCache(for: episodeID)
              } catch {
                log.caughtError(
                  "cacheSelectedEpisodes: failed for episode \(episodeID)",
                  error
                )
              }
            }
          }
        }
      } catch {
        log.caughtError("cacheSelectedEpisodes: failed to resolve episode IDs", error)
      }
    }
  }

  func uncacheSelectedEpisodes() {
    let cachedEpisodeIDs =
      selectedEpisodes
      .filter { $0.episodeID != nil && $0.cacheStatus == .cached }
      .compactMap(\.episodeID)
    guard !cachedEpisodeIDs.isEmpty else { return }

    let log = Self.log
    Task {
      await withDiscardingTaskGroup { group in
        for episodeID in cachedEpisodeIDs {
          group.addTask {
            do {
              try await Container.shared.repo().updateSaveInCache(episodeID, saveInCache: false)
            } catch {
              log.caughtError(
                "uncacheSelectedEpisodes: failed to unsave episode \(episodeID)",
                error
              )
            }
            do {
              try await Container.shared.cacheManager().clearCache(for: episodeID)
            } catch {
              log.caughtError(
                "uncacheSelectedEpisodes: failed to clear cache for episode \(episodeID)",
                error
              )
            }
          }
        }
      }
    }
  }

  func saveSelectedEpisodesInCache() {
    guard anySelectedNotSavedInCache else { return }

    let log = Self.log
    Task { [weak self] in
      guard let self else { return }

      let episodeIDs: [Episode.ID]
      do {
        episodeIDs = try await selectedPodcastEpisodeIDs
      } catch {
        log.caughtError("saveSelectedEpisodesInCache: failed to resolve episode IDs", error)
        return
      }

      await withDiscardingTaskGroup { group in
        for episodeID in episodeIDs {
          group.addTask {
            do {
              try await Container.shared.repo().updateSaveInCache(episodeID, saveInCache: true)
            } catch {
              log.caughtError(
                "saveSelectedEpisodesInCache: failed to save episode \(episodeID)",
                error
              )
              return
            }
            do {
              try await Container.shared.cacheManager().downloadToCache(for: episodeID)
            } catch {
              log.caughtError(
                "saveSelectedEpisodesInCache: failed to cache episode \(episodeID)",
                error
              )
            }
          }
        }
      }
    }
  }

  func unsaveSelectedEpisodesFromCache() {
    let savedEpisodeIDs =
      selectedEpisodes
      .filter { $0.episodeID != nil && $0.saveInCache }
      .compactMap(\.episodeID)
    guard !savedEpisodeIDs.isEmpty else { return }

    let log = Self.log
    Task {
      await withDiscardingTaskGroup { group in
        for episodeID in savedEpisodeIDs {
          group.addTask {
            do {
              try await Container.shared.repo().updateSaveInCache(episodeID, saveInCache: false)
            } catch {
              log.caughtError(
                "unsaveSelectedEpisodesFromCache: failed to unsave episode \(episodeID)",
                error
              )
            }
          }
        }
      }
    }
  }

  func cancelSelectedEpisodeDownloads() {
    let downloadingEpisodeIDs =
      selectedEpisodes
      .filter { $0.episodeID != nil && $0.cacheStatus == .caching }
      .compactMap(\.episodeID)
    guard !downloadingEpisodeIDs.isEmpty else { return }

    let log = Self.log
    Task {
      await withDiscardingTaskGroup { group in
        for episodeID in downloadingEpisodeIDs {
          group.addTask {
            do {
              try await Container.shared.cacheManager().clearCache(for: episodeID)
            } catch {
              log.caughtError(
                "cancelSelectedEpisodeDownloads: failed for episode \(episodeID)",
                error
              )
            }
          }
        }
      }
    }
  }

  func markSelectedEpisodesFinished() {
    guard anySelectedUnfinished else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let episodeIDs = try await selectedPodcastEpisodeIDs
        try await repo.markFinished(episodeIDs)
      } catch {
        Self.log.caughtError("markSelectedEpisodesFinished: failed", error)
      }
    }
  }
}

extension SelectableEpisodeList where EpisodeType == PodcastEpisode {
  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws { selectedEpisodes } }
}
