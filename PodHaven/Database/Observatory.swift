// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import IdentifiedCollections

typealias PodcastArray = IdentifiedArray<URL, Podcast>
typealias PodcastEpisodeArray = IdentifiedArrayOf<PodcastEpisode>

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
        .filter(Column("queueOrder") != nil)
        .including(required: Episode.podcast)
        .order(Column("queueOrder").asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchIdentifiedArray(db)
    }
    .removeDuplicates()
    .shared(in: Repo.shared.db)
}
