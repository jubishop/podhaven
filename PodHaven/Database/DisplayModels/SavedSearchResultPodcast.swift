// Copyright Justin Bishop, 2026

import Foundation

struct SavedSearchResultPodcast: Hashable, Sendable {
  let resultFeedURL: FeedURL
  let originalPodcast: UnsavedPodcast
  let originalEpisodeCount: Int
  let originalMostRecentEpisodeDate: Date?
  let savedPodcast: ListablePodcast

  // Hash/equality on the canonical podcast (not resultFeedURL) so SwiftUI
  // diffs by content, not by which search slot the row occupies.
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
