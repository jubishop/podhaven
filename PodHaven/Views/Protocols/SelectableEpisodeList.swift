// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

@MainActor protocol SelectableEpisodeList: AnyObject {
  associatedtype EpisodeType: EpisodeDisplayable
  associatedtype EpisodeID: Hashable

  var isSelecting: Bool { get set }
  var episodeList: SelectableListUseCase<EpisodeType, EpisodeID> { get set }
  var selectedEpisodes: [EpisodeType] { get }
  var selectedEpisodeIDs: [EpisodeID] { get }

  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws }
  var selectedPodcastEpisodeIDs: [Episode.ID] { get async throws }

  func addSelectedEpisodesToTopOfQueue()
  func addSelectedEpisodesToBottomOfQueue()
  func replaceQueueWithSelected()
  func replaceQueueWithSelectedAndPlay()
  func cacheSelectedEpisodes()
  func uncacheSelectedEpisodes()
  func cancelSelectedEpisodeDownloads()
  func markSelectedEpisodesFinished()

  var anySelectedNotCached: Bool { get }
  var anySelectedCached: Bool { get }
  var anySelectedCaching: Bool { get }
  var anySelectedUnfinished: Bool { get }
}

extension SelectableEpisodeList {
  private var playManager: PlayManager { Container.shared.playManager() }
  private var queue: any Queueing { Container.shared.queue() }
  private var repo: any Databasing { Container.shared.repo() }

  private var log: Logger { Log.as(LogSubsystem.ViewProtocols.episodeList) }

  var selectedEpisodes: [EpisodeType] { episodeList.selectedEntries.elements }
  var selectedEpisodeIDs: [EpisodeID] { Array(episodeList.selectedEntries.ids) }
  var selectedPodcastEpisodeIDs: [Episode.ID] {
    get async throws {
      try await selectedPodcastEpisodes.map(\.id)
    }
  }

  func addSelectedEpisodesToBottomOfQueue() {
    Task { [weak self] in
      guard let self else { return }
      guard !selectedEpisodes.isEmpty else { return }

      let episodeIDs = try await selectedPodcastEpisodeIDs
      try await queue.append(episodeIDs)
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    Task { [weak self] in
      guard let self else { return }
      guard !selectedEpisodes.isEmpty else { return }

      let episodeIDs = try await selectedPodcastEpisodeIDs
      try await queue.unshift(episodeIDs)
    }
  }

  func replaceQueueWithSelected() {
    Task { [weak self] in
      guard let self else { return }
      guard !selectedEpisodes.isEmpty else { return }

      let episodeIDs = try await selectedPodcastEpisodeIDs
      try await queue.replace(episodeIDs)
    }
  }

  func replaceQueueWithSelectedAndPlay() {
    Task { [weak self] in
      guard let self else { return }
      guard !selectedEpisodes.isEmpty else { return }

      let podcastEpisodes = try await selectedPodcastEpisodes
      if let firstPodcastEpisode = podcastEpisodes.first {
        try await playManager.load(firstPodcastEpisode)
        await playManager.play()
        let allExceptFirstPodcastEpisode = podcastEpisodes.dropFirst()
        try await queue.replace(allExceptFirstPodcastEpisode.map(\.id))
      }
    }
  }

  func cacheSelectedEpisodes() {
    Task { [weak self] in
      guard let self else { return }
      guard anySelectedNotCached else { return }

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
      guard anySelectedCached else { return }

      let cachedEpisodeIDs =
        try await selectedPodcastEpisodes
        .filter(\.episode.cached)
        .map(\.id)

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
      guard anySelectedCaching else { return }

      let downloadingEpisodeIDs =
        try await selectedPodcastEpisodes
        .filter(\.episode.caching)
        .map(\.id)

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
    Task { [weak self] in
      guard let self else { return }
      guard anySelectedUnfinished else { return }

      let episodeIDs = try await selectedPodcastEpisodeIDs
      try await repo.markFinished(episodeIDs)
    }
  }

  var anySelectedNotCached: Bool {
    selectedEpisodes.contains { !$0.cached }
  }

  var anySelectedCached: Bool {
    selectedEpisodes.contains { $0.cached }
  }

  var anySelectedCaching: Bool {
    selectedEpisodes.contains { $0.caching }
  }

  var anySelectedUnfinished: Bool {
    selectedEpisodes.contains { !$0.finished }
  }
}

extension SelectableEpisodeList where EpisodeType == PodcastEpisode {
  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws { selectedEpisodes } }
}
