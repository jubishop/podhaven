// Copyright Justin Bishop, 2026

import Foundation
import GRDB
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

  // MARK: - Fetch

  // Single source of truth for the three-query detail fetch — used by the
  // one-shot `Repo.podcastSeriesDetail(_:)` read and the live
  // `Observatory.podcastSeriesDetail(_:)` ValueObservation. ValueObservation
  // auto-tracks every table referenced inside the closure, so observers
  // wake on changes to `podcast`, `episode`, `episodeTag`, or `podcastTag`.
  static func fetchOne(_ podcastID: Podcast.ID, in db: Database) throws -> PodcastSeriesDetail? {
    guard let podcast = try Podcast.withID(podcastID).fetchOne(db) else { return nil }
    let episodes =
      try ListableEpisode
      .filter(Episode.Columns.podcastId == podcastID)
      .order(Episode.Columns.pubDate.desc)
      .fetchAll(db)
    let tags =
      try Tag
      .joining(required: Tag.podcastTags.filter(PodcastTag.Columns.podcastId == podcastID))
      .orderedByName()
      .fetchAll(db)
    return PodcastSeriesDetail(
      podcast: podcast,
      episodes: IdentifiedArrayOf(uniqueElements: episodes),
      tags: IdentifiedArrayOf(uniqueElements: tags)
    )
  }
}
