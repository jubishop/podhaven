// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct EpisodeTranscriptionCheckpoint:
  Codable,
  FetchableRecord,
  PersistableRecord,
  Sendable,
  TableRecord
{
  static let databaseTableName = "episodeTranscriptionCheckpoint"

  let episodeId: Episode.ID
  let checkpointJSON: String

  static let episode = belongsTo(Episode.self)

  enum Columns {
    static let episodeId = Column("episodeId")
    static let checkpointJSON = Column("checkpointJSON")
  }

  init(episodeId: Episode.ID, checkpoint: TranscriptionCheckpoint) throws {
    self.episodeId = episodeId
    self.checkpointJSON = try checkpoint.jsonString()
  }

  func checkpoint() throws -> TranscriptionCheckpoint {
    try TranscriptionCheckpoint(decoding: checkpointJSON)
  }
}
