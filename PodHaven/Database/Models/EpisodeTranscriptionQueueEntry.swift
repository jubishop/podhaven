// Copyright Justin Bishop, 2026

import GRDB

enum TranscriptionWorkMode:
  String,
  Codable,
  DatabaseValueConvertible,
  Hashable,
  Sendable
{
  case publisherPreferred
  case onDeviceReplacement
}

struct TranscriptionWork: Equatable, Hashable, Sendable {
  let episodeID: Episode.ID
  let mode: TranscriptionWorkMode
}

enum PublisherTranscriptReplacementResult: Sendable {
  case replaced
  case publisherTranscriptUnavailable
  case workModeChanged
}

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
  let workMode: TranscriptionWorkMode

  enum Columns {
    static let position = Column("position")
    static let episodeId = Column("episodeId")
    static let workMode = Column("workMode")
  }

  init(
    episodeId: Episode.ID,
    workMode: TranscriptionWorkMode = .publisherPreferred
  ) {
    position = nil
    self.episodeId = episodeId
    self.workMode = workMode
  }

  var work: TranscriptionWork {
    TranscriptionWork(episodeID: episodeId, mode: workMode)
  }
}
