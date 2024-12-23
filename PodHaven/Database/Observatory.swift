// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct Observatory: Sendable {
  // MARK:- Observers

  static let allPodcasts: SharedValueObservation<PodcastArray> =
    ValueObservation
    .tracking { db in
      try Podcast.all().fetchIdentifiedArray(db, id: \Podcast.feedURL)
    }
    .removeDuplicates()
    .shared(in: Repo.shared.db)
}
