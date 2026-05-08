// Copyright Justin Bishop, 2026

import Foundation

// Pairs an `Episode` with the tag IDs assigned to it. Used as the element
// type of `PodcastSeries.episodes` so each row carries its own tag set
// instead of leaning on a parallel dictionary on the parent series.
//
// `tagIDs == nil` means tag data wasn't loaded with this episode (e.g. the
// JSON-decoder path used by `asRequest(of:)`); a populated Set — possibly
// empty — means the row has its current tags. Property access forwards to
// `Episode` via `@dynamicMemberLookup` so existing call sites that just
// read columns keep working unchanged; callers that need an `Episode`
// instance (e.g. to build a `PodcastEpisode` or call a method) extract
// `.episode` explicitly.
@dynamicMemberLookup
struct EpisodeWithTags: Equatable, Hashable, Identifiable, Sendable {
  let episode: Episode
  let tagIDs: Set<Tag.ID>?

  var id: Episode.ID { episode.id }

  subscript<T>(dynamicMember keyPath: KeyPath<Episode, T>) -> T {
    episode[keyPath: keyPath]
  }
}
