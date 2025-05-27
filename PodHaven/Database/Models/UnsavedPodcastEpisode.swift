// Copyright Justin Bishop, 2025

import Foundation

struct UnsavedPodcastEpisode: Codable, Equatable, Hashable, Identifiable, Searchable, Stringable {
  var id: MediaURL { unsavedEpisode.media }

  // MARK: - Stringable / Searchable

  var toString: String { unsavedEpisode.toString }
  var searchableString: String { unsavedEpisode.searchableString }

  // MARK: - Data

  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode
}
