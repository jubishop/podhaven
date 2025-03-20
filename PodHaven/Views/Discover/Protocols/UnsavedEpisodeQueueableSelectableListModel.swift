// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections

@MainActor protocol UnsavedEpisodeQueueableSelectableListModel: QueueableSelectableList {
  var unsavedPodcast: UnsavedPodcast { get set }
  var episodeList: SelectableListUseCase<UnsavedEpisode, GUID> { get set }
  var filteredUnsavedPodcastEpisodes: [UnsavedPodcastEpisode] { get }
}

@MainActor extension UnsavedEpisodeQueueableSelectableListModel {
  var filteredUnsavedPodcastEpisodes: [UnsavedPodcastEpisode] {
    episodeList.selectedEntries.map { unsavedEpisode in
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    Task {
      let repo = Container.shared.repo()
      let podcastEpisodes = try await repo.upsertPodcastEpisodes(filteredUnsavedPodcastEpisodes)
      try await Container.shared.queue().unshift(podcastEpisodes.map(\.id))
    }
  }

  func addSelectedEpisodesToBottomOfQueue() {
    Task {
      let repo = Container.shared.repo()
      let podcastEpisodes = try await repo.upsertPodcastEpisodes(filteredUnsavedPodcastEpisodes)
      try await Container.shared.queue().append(podcastEpisodes.map(\.id))
    }
  }

  func replaceQueue() {
    Task {
      let repo = Container.shared.repo()
      let podcastEpisodes = try await repo.upsertPodcastEpisodes(filteredUnsavedPodcastEpisodes)
      try await Container.shared.queue().replace(podcastEpisodes.map(\.id))
    }
  }

  func replaceQueueAndPlay() {
    Task {
      let repo = Container.shared.repo()
      let podcastEpisodes = try await repo.upsertPodcastEpisodes(filteredUnsavedPodcastEpisodes)
      if let firstPodcastEpisode = podcastEpisodes.first {
        try await Container.shared.playManager().load(firstPodcastEpisode)
        await Container.shared.playManager().play()
        let allExceptFirstPodcastEpisode = podcastEpisodes.dropFirst()
        try await Container.shared.queue().replace(allExceptFirstPodcastEpisode.map(\.id))
      }
    }
  }
}
