// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor class TrendingItemEpisodeDetailViewModel {
  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode

  init(unsavedPodcast: UnsavedPodcast, unsavedEpisode: UnsavedEpisode) {
    self.unsavedPodcast = unsavedPodcast
    self.unsavedEpisode = unsavedEpisode
  }
}

