// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

@MainActor protocol SelectableEpisodeList: AnyObject {
  associatedtype EpisodeType: EpisodeDisplayable

  var isSelecting: Bool { get set }
  var episodeList: SelectableListUseCase<EpisodeType> { get }

  var selectedEpisodes: [EpisodeType] { get }
  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws }
  var selectedPodcastEpisodeIDs: [Episode.ID] { get async throws }

  var anySelectedQueued: Bool { get }
  var anySelectedNotAtTopOfQueue: Bool { get }
  var anySelectedNotAtBottomOfQueue: Bool { get }
  var anySelectedNotQueued: Bool { get }
  var anySelectedNotCached: Bool { get }
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
  func cancelSelectedEpisodeDownloads()
  func markSelectedEpisodesFinished()
}

extension SelectableEpisodeList {
  private var cacheManager: CacheManager { Container.shared.cacheManager() }
  private var playManager: PlayManager { Container.shared.playManager() }
  private var playState: PlayState { Container.shared.playState() }
  private var queue: any Queueing { Container.shared.queue() }
  private var repo: any Databasing { Container.shared.repo() }

  private var log: Logger { Log.as(LogSubsystem.ViewProtocols.episodeList) }

  var selectedEpisodes: [EpisodeType] { episodeList.selectedEntries.elements }
  var selectedPodcastEpisodeIDs: [Episode.ID] {
    get async throws {
      try await selectedPodcastEpisodes.map(\.id)
    }
  }

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
    selectedEpisodes.contains { $0.queueOrder != playState.maxQueuePosition }
  }

  var anySelectedNotCached: Bool {
    selectedEpisodes.contains { $0.cacheStatus != .cached }
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

  func addSelectedEpisodesToBottomOfQueue() {
    guard !selectedEpisodes.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      let episodeIDs = try await selectedPodcastEpisodeIDs
      try await queue.append(episodeIDs)
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    guard !selectedEpisodes.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      let episodeIDs = try await selectedPodcastEpisodeIDs
      try await queue.unshift(episodeIDs)
    }
  }

  func replaceQueueWithSelected() {
    guard !selectedEpisodes.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      let episodeIDs = try await selectedPodcastEpisodeIDs
      try await queue.replace(episodeIDs)
    }
  }

  func playSelectedEpisodes() {
    guard !selectedEpisodes.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      let podcastEpisodes = try await selectedPodcastEpisodes
      if let firstPodcastEpisode = podcastEpisodes.first {
        try await playManager.load(firstPodcastEpisode)
        await playManager.play()
      }
      let allExceptFirstPodcastEpisode = podcastEpisodes.dropFirst()
      try await queue.unshift(allExceptFirstPodcastEpisode.map(\.id))
    }
  }

  func dequeueSelectedEpisodes() {
    guard !selectedEpisodes.isEmpty else { return }

    Task { [weak self] in
      guard let self else { return }

      let episodeIDs = try await selectedPodcastEpisodeIDs
      try await queue.dequeue(episodeIDs)
    }
  }

  func cacheSelectedEpisodes() {
    guard anySelectedNotCached else { return }

    Task { [weak self] in
      guard let self else { return }

      try await withThrowingTaskGroup(of: Void.self) { group in
        for episodeID in try await selectedPodcastEpisodeIDs {
          group.addTask {
            try await Container.shared.cacheManager().downloadToCache(for: episodeID)
          }
        }
      }
    }
  }

  func uncacheSelectedEpisodes() {
    Task { [weak self] in
      guard let self else { return }

      let cachedEpisodeIDs =
        try await selectedPodcastEpisodes
        .filter { $0.episode.cacheStatus == .cached }
        .map(\.id)
      guard !cachedEpisodeIDs.isEmpty else { return }

      await withThrowingTaskGroup(of: Void.self) { group in
        for episodeID in cachedEpisodeIDs {
          group.addTask {
            try await Container.shared.cacheManager().clearCache(for: episodeID)
          }
        }
      }
    }
  }

  func cancelSelectedEpisodeDownloads() {
    Task { [weak self] in
      guard let self else { return }

      let downloadingEpisodeIDs =
        try await selectedPodcastEpisodes
        .filter { $0.episode.cacheStatus == .caching }
        .map(\.id)
      guard !downloadingEpisodeIDs.isEmpty else { return }

      await withThrowingTaskGroup(of: Void.self) { group in
        for episodeID in downloadingEpisodeIDs {
          group.addTask {
            try await Container.shared.cacheManager().clearCache(for: episodeID)
          }
        }
      }
    }
  }

  func markSelectedEpisodesFinished() {
    guard anySelectedUnfinished else { return }

    Task { [weak self] in
      guard let self else { return }

      let episodeIDs = try await selectedPodcastEpisodeIDs
      try await repo.markFinished(episodeIDs)
    }
  }
}

extension SelectableEpisodeList where EpisodeType == PodcastEpisode {
  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws { selectedEpisodes } }
}
