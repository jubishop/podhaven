// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Narrow projection of `Episode` carrying only the columns scoring math
// reads: id (lookup key for embeddings + score map), podcastID (affinity
// + freshness cadence lookup), pubDate (freshness multiplier + tiebreaker).
// Used by `Repo.allCandidateEpisodes` so the per-rebuild fetch skips heavy
// payload columns (description, playbackCoverage, image, etc.) on every
// candidate row.
struct CandidateEpisode:
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
      Episode.Columns.pubDate,
    ]
  }

  let id: Episode.ID
  let podcastID: Podcast.ID
  let pubDate: Date

  init(id: Episode.ID, podcastID: Podcast.ID, pubDate: Date) {
    self.id = id
    self.podcastID = podcastID
    self.pubDate = pubDate
  }

  init(row: Row) throws {
    self.id = row[Episode.Columns.id]
    self.podcastID = row[Episode.Columns.podcastId]
    self.pubDate = row[Episode.Columns.pubDate]
  }
}
