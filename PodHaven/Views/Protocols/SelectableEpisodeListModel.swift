// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

@MainActor protocol SelectableEpisodeListModel: AnyObject, SelectableEpisodeList {
  associatedtype EpisodeType: Searchable
  associatedtype EpisodeID: Hashable

  var isSelecting: Bool { get set }
  var episodeList: SelectableListUseCase<EpisodeType, EpisodeID> { get set }
  var selectedEpisodes: [EpisodeType] { get }
  var selectedEpisodeIDs: [EpisodeID] { get }

  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws }
  var selectedPodcastEpisodeIDs: [Episode.ID] { get async throws }
}

extension SelectableEpisodeListModel {
  private var playManager: PlayManager { Container.shared.playManager() }
  private var queue: any Queueing { Container.shared.queue() }

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
      guard !selectedEpisodes.isEmpty else { return }
      try await withThrowingTaskGroup(of: Void.self) { group in
        for podcastEpisode in try await selectedPodcastEpisodes {
          group.addTask {
            try await Container.shared.cacheManager().downloadAndCache(podcastEpisode)
          }
        }
      }
    }
  }
}

extension SelectableEpisodeListModel where EpisodeType == PodcastEpisode {
  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws { selectedEpisodes } }
}
