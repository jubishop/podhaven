// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@MainActor protocol UnsavedPodcastObservableModel: AnyObject, Observable {
  var unsavedPodcast: UnsavedPodcast { get set }
  var episodeList: SelectableListUseCase<UnsavedEpisode, GUID> { get set }
  var existingPodcastSeries: PodcastSeries? { get set }
  var podcastFeed: PodcastFeed? { get }
  
  func processPodcastSeries(_ podcastSeries: PodcastSeries?) throws
}

@MainActor extension UnsavedPodcastObservableModel {
  func processPodcastSeries(_ podcastSeries: PodcastSeries?) throws {
    guard let podcastFeed = self.podcastFeed
    else { throw Err.msg("Can't call processPodcastSeries without a podcastFeed") }

    existingPodcastSeries = podcastSeries
    if let podcastSeries = existingPodcastSeries {
      unsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries.podcast.unsaved)
    } else {
      unsavedPodcast = try podcastFeed.toUnsavedPodcast(subscribed: false, lastUpdate: Date.epoch)
    }

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
