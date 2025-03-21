// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections

@MainActor protocol UnsavedQueueableSelectableListModel: QueueableSelectableList {
  var episodeList: SelectableListUseCase<UnsavedEpisode, GUID> { get set }
  var filteredUnsavedPodcastEpisodes: [UnsavedPodcastEpisode] { get }
  var unsavedEpisodes: [UnsavedEpisode] { get }
  var unsavedPodcast: UnsavedPodcast { get set }

  func processEpisodes(
    from podcastFeed: PodcastFeed,
    merging existingPodcastSeries: PodcastSeries?
  ) throws
}

@MainActor extension UnsavedQueueableSelectableListModel {
  var unsavedEpisodes: [UnsavedEpisode] { Array(episodeList.allEntries) }

  var filteredUnsavedPodcastEpisodes: [UnsavedPodcastEpisode] {
    episodeList.selectedEntries.map { unsavedEpisode in
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    }
  }

  func processEpisodes(
    from podcastFeed: PodcastFeed,
    merging existingPodcastSeries: PodcastSeries?
  ) throws {
    episodeList.allEntries = IdentifiedArray(
      uniqueElements: try podcastFeed.episodes.map { episodeFeed in
        try episodeFeed.toUnsavedEpisode(
          merging: existingPodcastSeries?.episodes[id: episodeFeed.guid]
        )
      },
      id: \.guid
    )
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
