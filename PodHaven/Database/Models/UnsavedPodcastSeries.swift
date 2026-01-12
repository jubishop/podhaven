// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

struct UnsavedPodcastSeries: Equatable, Hashable, Identifiable, Stringable {
  var id: FeedURL { unsavedPodcast.id }

  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisodes: IdentifiedArrayOf<UnsavedEpisode>

  init(unsavedPodcast: UnsavedPodcast, unsavedEpisodes: [UnsavedEpisode] = []) {
    self.init(
      unsavedPodcast: unsavedPodcast,
      unsavedEpisodes: IdentifiedArrayOf(uniqueElements: unsavedEpisodes)
    )
  }

  init(unsavedPodcast: UnsavedPodcast, unsavedEpisodes: IdentifiedArrayOf<UnsavedEpisode>) {
    self.unsavedPodcast = unsavedPodcast
    self.unsavedEpisodes = unsavedEpisodes
  }

  // MARK: - Stringable

  var toString: String { unsavedPodcast.toString }
}
