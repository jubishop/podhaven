// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct PublisherTranscriptImportJob:
  Codable,
  FetchableRecord,
  PersistableRecord,
  Sendable,
  TableRecord
{
  static let databaseTableName = "publisherTranscriptImportJob"

  let episodeId: Episode.ID
  let attemptCount: Int
  let nextAttemptAt: Date

  enum Columns {
    static let episodeId = Column("episodeId")
    static let attemptCount = Column("attemptCount")
    static let nextAttemptAt = Column("nextAttemptAt")
  }

  init(
    episodeId: Episode.ID,
    attemptCount: Int = 0,
    nextAttemptAt: Date
  ) {
    self.episodeId = episodeId
    self.attemptCount = attemptCount
    self.nextAttemptAt = nextAttemptAt
  }
}
