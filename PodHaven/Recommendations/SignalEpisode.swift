// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// `databaseSelection` is intentionally narrow: filtering on `Episode.rated`
// against this projection caps GRDB's tracked region to the rating columns,
// so playback-path UPDATEs (currentTime, playbackCoverage, lastPlayedDate)
// can't fire any observation built on it.
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
    ]
  }

  let id: Episode.ID
  let podcastID: Podcast.ID
  let rating: EpisodeRating
  let ratingDate: Date?

  init(row: Row) throws {
    self.id = row[Episode.Columns.id]
    self.podcastID = row[Episode.Columns.podcastId]
    guard let rating = row[Episode.Columns.rating] as EpisodeRating? else {
      Assert.fatal("SignalEpisode requires Episode.rated filter; row had nil rating")
    }
    self.rating = rating
    self.ratingDate = row[Episode.Columns.ratingDate]
  }
}
