// Copyright Justin Bishop, 2025

import Foundation

struct UnsavedPodcastEpisode: Sendable, Hashable {
  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode
}
