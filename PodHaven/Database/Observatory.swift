// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

extension Container {
  var observatory: Factory<Observatory> {
    Factory(self) { Observatory() }.scope(.singleton)
  }
}

struct Observatory {
  func podcastEpisode(_ mediaURL: MediaURL) -> AsyncValueObservation<PodcastEpisode?> {
    ValueObservation
      .tracking(
        Episode
          .filter(Schema.mediaColumn == mediaURL)
          .including(required: Episode.podcast)
          .asRequest(of: PodcastEpisode.self)
          .fetchOne
      )
      .removeDuplicates()
      .values(in: Container.shared.repo().db)
  }

  func podcastSeries(_ feedURL: FeedURL) -> AsyncValueObservation<PodcastSeries?> {
    ValueObservation
      .tracking(
        Podcast
          .filter(Schema.feedURLColumn == feedURL)
          .including(all: Podcast.episodes)
          .asRequest(of: PodcastSeries.self)
          .fetchOne
      )
      .removeDuplicates()
      .values(in: Container.shared.repo().db)
  }
}
