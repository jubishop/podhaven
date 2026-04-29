// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import GRDB

// Read-on-rebuild only. This selection includes high-churn columns
// (playbackCoverage, lastPlayedDate) that must NOT enter any GRDB
// observation — fetch via `allUnratedListenedEpisodes()` or the merged-stream
// rebuild path, never inside a `_observe` closure.
struct PartialSignal:
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
      Episode.Columns.duration,
      Episode.Columns.playbackCoverage,
      Episode.Columns.lastPlayedDate,
    ]
  }

  let id: Episode.ID
  let podcastID: Podcast.ID
  let coverageRatio: Double
  let lastPlayedDate: Date?

  init(row: Row) throws {
    self.id = row[Episode.Columns.id]
    self.podcastID = row[Episode.Columns.podcastId]
    self.lastPlayedDate = row[Episode.Columns.lastPlayedDate]

    guard let bitmap: Data = row[Episode.Columns.playbackCoverage] else {
      Assert.fatal("PartialSignal requires Episode.hasCoverage filter; row had nil bitmap")
    }

    let duration: CMTime? = row[Episode.Columns.duration]
    let durationSeconds = duration?.positiveFiniteSeconds ?? 0
    if durationSeconds > 0 {
      let coverage = PlaybackCoverage(durationSeconds: durationSeconds, data: bitmap)
      self.coverageRatio = coverage.ratio
    } else {
      self.coverageRatio = 0
    }
  }
}
