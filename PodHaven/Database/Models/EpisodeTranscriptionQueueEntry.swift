// Copyright Justin Bishop, 2026

import GRDB

struct EpisodeTranscriptionQueueEntry:
  Codable,
  FetchableRecord,
  PersistableRecord,
  Sendable,
  TableRecord
{
  static let databaseTableName = "episodeTranscriptionQueue"

  let position: Int64?
  let episodeId: Episode.ID

  enum Columns {
    static let position = Column("position")
    static let episodeId = Column("episodeId")
  }

  init(episodeId: Episode.ID) {
    position = nil
    self.episodeId = episodeId
  }
}
