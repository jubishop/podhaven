// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import IdentifiedCollections

typealias PodcastArray = IdentifiedArray<URL, Podcast>
typealias PodcastEpisodeArray = IdentifiedArray<URL, PodcastEpisode>

struct Observatory: Sendable {
  // MARK:- Observers

  static let allPodcasts: SharedValueObservation<PodcastArray> =
    ValueObservation
    .tracking { db in
      try Podcast
        .all()
        .fetchIdentifiedArray(db, id: \Podcast.feedURL)
    }
    .removeDuplicates()
    .shared(in: Repo.shared.db)

  static let queuedEpisodes: SharedValueObservation<PodcastEpisodeArray> =
    ValueObservation.tracking { db in
      try Episode
        .filter(AppDB.queueOrderColumn != nil)
        .including(required: Episode.podcast)
        .order(AppDB.queueOrderColumn.asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchIdentifiedArray(db, id: \PodcastEpisode.episode.media)
    }
    .removeDuplicates()
    .shared(in: Repo.shared.db)
}
