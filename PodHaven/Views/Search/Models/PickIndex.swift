// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// MARK: - PickIndex

// Maps each visible pick back to the cache entry that owns it, so removePick
// can find the owner without scanning every entry. Invariant: each scored
// episode lives in exactly one entry, so picks registered for one entry can
// never collide with another entry's keys.
@MainActor
struct PickIndex {
  private struct Key: Hashable {
    let feedURL: FeedURL
    let mediaGUID: MediaGUID
  }

  private var entriesByPick: [Key: CachedPodcastEntry] = [:]

  // Re-scoring an already-scored entry would leave stale keys behind, so this
  // un-indexes the entry's current picks first. Call before overwriting
  // `entry.scoredEpisodes` with `scored`.
  mutating func register(
    _ scored: IdentifiedArrayOf<SearchRecommendationCollector.ScoredEpisode>,
    for entry: CachedPodcastEntry
  ) {
    unregister(of: entry)
    for pick in scored {
      entriesByPick[Key(feedURL: entry.feedURL, mediaGUID: pick.id)] = entry
    }
  }

  mutating func unregister(of entry: CachedPodcastEntry) {
    for pick in entry.scoredEpisodes {
      entriesByPick.removeValue(forKey: Key(feedURL: entry.feedURL, mediaGUID: pick.id))
    }
  }

  // Returns the entry whose picks held the GUID, or nil. Entry-level cleanup
  // (dropping the pick, the .exhausted status flip) stays with the caller.
  mutating func remove(mediaGUID: MediaGUID, feedURL: FeedURL) -> CachedPodcastEntry? {
    entriesByPick.removeValue(forKey: Key(feedURL: feedURL, mediaGUID: mediaGUID))
  }
}
