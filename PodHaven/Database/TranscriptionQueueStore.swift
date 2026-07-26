// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB

extension Container {
  var transcriptionQueueStore: Factory<TranscriptionQueueStore> {
    Factory(self) {
      let appDB = self.appDB()
      return TranscriptionQueueStore(
        reader: appDB.reader,
        writer: appDB.writer
      )
    }
    .scope(.cached)
  }
}

struct TranscriptionQueueStore: Sendable {
  private let reader: AppDB.Reader
  private let writer: AppDB.Writer

  fileprivate init(reader: AppDB.Reader, writer: AppDB.Writer) {
    self.reader = reader
    self.writer = writer
  }

  func fetchAll() async throws -> [Episode.ID] {
    try await reader.read(Self.fetchAll)
  }

  func enqueue(_ episodeIDs: [Episode.ID]) async throws -> [Episode.ID] {
    try await writer.write { db in
      for episodeID in episodeIDs {
        try EpisodeTranscriptionQueueEntry(episodeId: episodeID)
          .insert(db, onConflict: .ignore)
      }
      return try Self.fetchAll(db)
    }
  }

  func remove(_ episodeID: Episode.ID) async throws -> [Episode.ID] {
    try await writer.write { db in
      try EpisodeTranscriptionQueueEntry
        .filter(EpisodeTranscriptionQueueEntry.Columns.episodeId == episodeID)
        .deleteAll(db)
      return try Self.fetchAll(db)
    }
  }

  private static func fetchAll(_ db: Database) throws -> [Episode.ID] {
    try EpisodeTranscriptionQueueEntry
      .order(EpisodeTranscriptionQueueEntry.Columns.position)
      .select(
        EpisodeTranscriptionQueueEntry.Columns.episodeId,
        as: Episode.ID.self
      )
      .fetchAll(db)
  }
}
