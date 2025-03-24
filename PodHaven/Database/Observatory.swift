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
  func allPodcasts(_ sqlExpression: SQLSpecificExpressible? = nil) -> AsyncValueObservation<
    PodcastArray
  > {
    let request = Podcast.all().filtered(with: sqlExpression)
    return _observe { db in
      try request.fetchIdentifiedArray(db, id: \Podcast.feedURL)
    }
  }

  func queuedEpisodes() -> AsyncValueObservation<PodcastEpisodeArray> {
    _observe { db in
      try Episode
        .filter(Schema.queueOrderColumn != nil)
        .including(required: Episode.podcast)
        .order(Schema.queueOrderColumn.asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchIdentifiedArray(db, id: \.episode.media)
    }
  }

  func podcastSeries(_ podcastID: Podcast.ID) -> AsyncValueObservation<PodcastSeries?> {
    _observe { db in
      try Podcast
        .filter(id: podcastID)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  func podcastEpisode(_ episodeID: Episode.ID) -> AsyncValueObservation<PodcastEpisode?> {
    _observe { db in
      try Episode
        .filter(id: episodeID)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func podcastEpisode(_ mediaURL: MediaURL) -> AsyncValueObservation<PodcastEpisode?> {
    _observe { db in
      try Episode
        .filter(Schema.mediaColumn == mediaURL)
        .including(required: Episode.podcast)
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }
  }

  func podcastSeries(_ feedURL: FeedURL) -> AsyncValueObservation<PodcastSeries?> {
    _observe { db in
      try Podcast
        .filter(Schema.feedURLColumn == feedURL)
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }
  }

  // Private Helpers

  private func _observe<T: Equatable>(_ block: @escaping @Sendable (Database) throws -> T)
    -> AsyncValueObservation<T>
  {
    ValueObservation.tracking(block)
      .removeDuplicates()
      .values(in: Container.shared.repo().db)
  }
}
