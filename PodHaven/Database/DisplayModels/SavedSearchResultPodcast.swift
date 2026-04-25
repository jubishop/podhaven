// Copyright Justin Bishop, 2026

import Foundation

struct SavedSearchResultPodcast: Hashable, Sendable {
  let resultFeedURL: FeedURL
  let originalPodcast: UnsavedPodcast
  let originalEpisodeCount: Int
  let originalMostRecentEpisodeDate: Date?
  let savedPodcast: ListablePodcast

  // Intentionally hashes/compares on the canonical podcast, not resultFeedURL.
  // id (resultFeedURL) drives IdentifiedArray slot identity; hash/equality answer
  // "is this the same underlying podcast data?" so SwiftUI diffing re-renders when
  // the podcast changes, not when the search slot does.
  func hash(into hasher: inout Hasher) {
    hasher.combine(savedPodcast)
  }

  static func == (lhs: SavedSearchResultPodcast, rhs: SavedSearchResultPodcast) -> Bool {
    lhs.savedPodcast == rhs.savedPodcast
  }

  func getPodcast() async throws -> Podcast {
    try await savedPodcast.getPodcast()
  }
}
