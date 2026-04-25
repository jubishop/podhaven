// Copyright Justin Bishop, 2026

import Foundation

struct SavedSearchResultPodcast: Hashable, Sendable {
  let resultFeedURL: FeedURL
  let originalPodcast: UnsavedPodcast
  let originalEpisodeCount: Int
  let originalMostRecentEpisodeDate: Date?
  let savedPodcast: ListablePodcast

  func getPodcast() async throws -> Podcast {
    try await savedPodcast.getPodcast()
  }
}
