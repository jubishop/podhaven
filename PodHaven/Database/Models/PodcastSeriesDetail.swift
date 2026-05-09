// Copyright Justin Bishop, 2026

import Foundation
import IdentifiedCollections

// Detail-view shape returned by `Repo.podcastSeriesDetail(...)` and
// `Observatory.podcastSeriesDetail(...)`. Carries:
//   * the parent `Podcast`
//   * a list of `ListableEpisode`s — the slim episode-row shape with tag
//     IDs materialised, *without* the joined Podcast columns the parent
//     already has
//   * the podcast's own tags (when the caller asked for them)
// Distinct from `PodcastSeries`, which keeps full `Episode` rows for the
// operational/refresh path.
struct PodcastSeriesDetail: Equatable, Hashable, Identifiable, Sendable, Stringable {
  var id: Podcast.ID { podcast.id }

  let podcast: Podcast
  let episodes: IdentifiedArrayOf<ListableEpisode>
  let tags: IdentifiedArrayOf<Tag>?

  init(
    podcast: Podcast,
    episodes: IdentifiedArrayOf<ListableEpisode> = [],
    tags: IdentifiedArrayOf<Tag>? = nil
  ) {
    self.podcast = podcast
    self.episodes = episodes
    self.tags = tags
  }

  // MARK: - Stringable

  var toString: String { podcast.toString }
}
