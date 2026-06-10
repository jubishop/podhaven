// Copyright Justin Bishop, 2026

import Foundation

// MARK: - ScoredEpisode

// A discovery pick that cleared the score floor, tagged with the cache-entry
// feedURL that owns it. The currency between the pipeline runner, the
// collector's cache, and the discovery list.
struct ScoredEpisode: Identifiable, Sendable, Hashable {
  var id: MediaGUID { episode.mediaGUID }
  let feedURL: FeedURL
  let episode: UnsavedPodcastEpisode
  let score: Float
}
