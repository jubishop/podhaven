// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections

@MainActor protocol QueueableSelectableEpisodeList: AnyObject, QueueableSelectableList {
  associatedtype EpisodeType: Stringable
  associatedtype EpisodeID: Hashable

  var episodeList: SelectableListUseCase<EpisodeType, EpisodeID> { get set }
  var selectedEpisodes: [EpisodeType] { get }

  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws }
  var selectedEpisodeIDs: [Episode.ID] { get async throws }
}

@MainActor extension QueueableSelectableEpisodeList {
  private var queue: Queue { Container.shared.queue() }
  private var playManager: PlayManager { get async { await Container.shared.playManager() } }

  var selectedEpisodes: [EpisodeType] { episodeList.selectedEntries.elements }

  func addSelectedEpisodesToBottomOfQueue() {
    Task { [weak self] in
      guard let self else { return }
      let episodeIDs = try await selectedEpisodeIDs
      try await queue.append(episodeIDs)
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    Task { [weak self] in
      guard let self else { return }
      let episodeIDs = try await selectedEpisodeIDs
      try await queue.unshift(episodeIDs)
    }
  }

  func replaceQueue() {
    Task { [weak self] in
      guard let self else { return }
      let episodeIDs = try await selectedEpisodeIDs
      try await queue.replace(episodeIDs)
    }
  }

  func replaceQueueAndPlay() {
    Task { [weak self] in
      guard let self else { return }
      let podcastEpisodes = try await selectedPodcastEpisodes
      if let firstPodcastEpisode = podcastEpisodes.first {
        try await playManager.load(firstPodcastEpisode)
        await playManager.play()
        let allExceptFirstPodcastEpisode = podcastEpisodes.dropFirst()
        try await queue.replace(allExceptFirstPodcastEpisode.map(\.id))
      }
    }
  }

  var selectedEpisodeIDs: [Episode.ID] {
    get async throws {
      try await selectedPodcastEpisodes.map(\.id)
    }
  }
}

@MainActor extension QueueableSelectableEpisodeList where EpisodeType == PodcastEpisode {
  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws { selectedEpisodes } }
}
