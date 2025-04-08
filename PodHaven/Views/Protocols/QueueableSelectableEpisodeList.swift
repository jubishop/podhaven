// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections

@MainActor protocol QueueableSelectableEpisodeList: QueueableSelectableList {
  associatedtype EpisodeType: Stringable
  associatedtype EpisodeID: Hashable

  var episodeList: SelectableListUseCase<EpisodeType, EpisodeID> { get set }
  var selectedEpisodes: [EpisodeType] { get }

  var selectedPodcastEpisodes: [PodcastEpisode] { get async throws }
  var selectedEpisodeIDs: [Episode.ID] { get async throws }
}

@MainActor extension QueueableSelectableEpisodeList {
  var selectedEpisodes: [EpisodeType] { episodeList.selectedEntries.elements }

  func addSelectedEpisodesToBottomOfQueue() {
    Task {
      let episodeIDs = try await selectedEpisodeIDs
      try await Container.shared.queue().append(episodeIDs)
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    Task {
      let episodeIDs = try await selectedEpisodeIDs
      try await Container.shared.queue().unshift(episodeIDs)
    }
  }

  func replaceQueue() {
    Task {
      let episodeIDs = try await selectedEpisodeIDs
      try await Container.shared.queue().replace(episodeIDs)
    }
  }

  func replaceQueueAndPlay() {
    Task {
      let podcastEpisodes = try await selectedPodcastEpisodes
      if let firstPodcastEpisode = podcastEpisodes.first {
        try await Container.shared.playManager().load(firstPodcastEpisode)
        await Container.shared.playManager().play()
        let allExceptFirstPodcastEpisode = podcastEpisodes.dropFirst()
        try await Container.shared.queue().replace(allExceptFirstPodcastEpisode.map(\.id))
      }
    }
  }
}
