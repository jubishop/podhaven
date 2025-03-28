// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections

@MainActor protocol UnsavedQueueableSelectableListModel: QueueableSelectableListModel
where EpisodeType == UnsavedEpisode, EpisodeID == GUID {
  var unsavedEpisodes: [UnsavedEpisode] { get }
  var unsavedPodcast: UnsavedPodcast { get set }

  func processEpisodes(
    from podcastFeed: PodcastFeed,
    merging existingPodcastSeries: PodcastSeries?
  ) throws
}

@MainActor extension UnsavedQueueableSelectableListModel {
  var unsavedEpisodes: [UnsavedEpisode] { Array(episodeList.allEntries) }

  var selectedUnsavedPodcastEpisodes: [UnsavedPodcastEpisode] {
    episodeList.selectedEntries.map { unsavedEpisode in
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    }
  }

  func upsertSelectedEpisodesToPodcastEpisodes() async throws -> [PodcastEpisode] {
    let repo = Container.shared.repo()
    return try await repo.upsertPodcastEpisodes(selectedUnsavedPodcastEpisodes)
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
}
