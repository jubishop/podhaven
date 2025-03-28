// Copyright Justin Bishop, 2025

import Foundation

struct UnsavedPodcastEpisode: Codable, Equatable, Hashable, Identifiable, Stringable {
  var id: MediaURL { unsavedEpisode.media }

  // MARK: - Stringable

  var toString: String { unsavedEpisode.title }

  // MARK: - Data

  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode
}
