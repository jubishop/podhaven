// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections

@MainActor protocol QueueableSelectableListModel: QueueableSelectableList {
  associatedtype EpisodeType: Stringable
  associatedtype EpisodeID: Hashable

  var episodeList: SelectableListUseCase<EpisodeType, EpisodeID> { get set }
  var selectedEpisodes: [EpisodeType] { get }

  func upsertSelectedEpisodes() async throws -> [PodcastEpisode]
}

@MainActor extension QueueableSelectableListModel {
  var selectedEpisodes: [EpisodeType] { episodeList.selectedEntries.elements }

  func addSelectedEpisodesToBottomOfQueue() {
    Task {
      let podcastEpisodes = try await upsertSelectedEpisodes()
      try await Container.shared.queue().append(podcastEpisodes.map(\.id))
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    Task {
      let podcastEpisodes = try await upsertSelectedEpisodes()
      try await Container.shared.queue().unshift(podcastEpisodes.map(\.id))
    }
  }

  func replaceQueue() {
    Task {
      let podcastEpisodes = try await upsertSelectedEpisodes()
      try await Container.shared.queue().replace(podcastEpisodes.map(\.id))
    }
  }

  func replaceQueueAndPlay() {
    Task {
      let podcastEpisodes = try await upsertSelectedEpisodes()
      if let firstPodcastEpisode = podcastEpisodes.first {
        try await Container.shared.playManager().load(firstPodcastEpisode)
        await Container.shared.playManager().play()
        let allExceptFirstPodcastEpisode = podcastEpisodes.dropFirst()
        try await Container.shared.queue().replace(allExceptFirstPodcastEpisode.map(\.id))
      }
    }
  }
}
