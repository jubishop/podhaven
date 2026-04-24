// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Classifies why an episode counts as a signal for recommendations.
// Explicit ratings take precedence over implicit finished-playback signals.
enum SignalKind: Sendable, Hashable {
  case rating(EpisodeRating)
  case finished
}

// Narrow projection of an Episode row holding only the columns the
// recommendation engine actually reads. Conforms to `TableRecord` against
// the Episode table with a `databaseSelection` of just those columns, so
// `SignalEpisode.filter(Episode.signal).fetchAll(db)` shrinks both the data
// fetched AND GRDB's column tracking — unrelated Episode updates (e.g.
// currentTime) won't re-run any observation built on this request.
struct SignalEpisode:
  Sendable,
  Identifiable,
  Equatable,
  FetchableRecord,
  TableRecord
{
  static let databaseTableName: String = Episode.databaseTableName
  static var databaseSelection: [any SQLSelectable] {
    [
      Episode.Columns.id,
      Episode.Columns.podcastId,
      Episode.Columns.rating,
      Episode.Columns.ratingDate,
      Episode.Columns.finishDate,
    ]
  }

  let id: Episode.ID
  let podcastID: Podcast.ID
  let kind: SignalKind
  let ratingDate: Date?
  let finishDate: Date?

  init(
    id: Episode.ID,
    podcastID: Podcast.ID,
    kind: SignalKind,
    ratingDate: Date?,
    finishDate: Date?
  ) {
    self.id = id
    self.podcastID = podcastID
    self.kind = kind
    self.ratingDate = ratingDate
    self.finishDate = finishDate
  }

  init(row: Row) throws {
    let kind: SignalKind
    if let rating = row[Episode.Columns.rating] as EpisodeRating? {
      kind = .rating(rating)
    } else {
      kind = .finished
    }
    self.init(
      id: row[Episode.Columns.id],
      podcastID: row[Episode.Columns.podcastId],
      kind: kind,
      ratingDate: row[Episode.Columns.ratingDate],
      finishDate: row[Episode.Columns.finishDate]
    )
  }
}
