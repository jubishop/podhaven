// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB

extension Container {
  var transcriptionQueueStore: Factory<any TranscriptionQueueStoring> {
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

enum TranscriptionQueueError: Error, Equatable, LocalizedError, Sendable {
  case capacityExceeded(limit: Int, currentCount: Int, requestedCount: Int)

  var alertTitle: String {
    "Transcription Queue Full"
  }

  var errorDescription: String? {
    switch self {
    case .capacityExceeded(let limit, let currentCount, let requestedCount):
      """
      The transcription queue can hold \(limit) episodes and currently has \
      \(currentCount). Let existing work finish or remove episodes before \
      adding \(requestedCount) more.
      """
    }
  }
}

protocol TranscriptionQueueStoring: Sendable {
  func fetchAll() async throws -> [Episode.ID]
  func enqueue(
    _ episodeIDs: [Episode.ID],
    maximumCount: Int
  ) async throws -> [Episode.ID]
  func remove(_ episodeID: Episode.ID) async throws
  func reorder(_ orderedEpisodeIDs: [Episode.ID]) async throws -> Bool
}

struct TranscriptionQueueStore: TranscriptionQueueStoring, Sendable {
  private let reader: AppDB.Reader
  private let writer: AppDB.Writer

  fileprivate init(reader: AppDB.Reader, writer: AppDB.Writer) {
    self.reader = reader
    self.writer = writer
  }

  func fetchAll() async throws -> [Episode.ID] {
    try await reader.read(Self.fetchAll)
  }

  func enqueue(
    _ episodeIDs: [Episode.ID],
    maximumCount: Int
  ) async throws -> [Episode.ID] {
    try await writer.write { db in
      var seen = Set<Episode.ID>()
      let uniqueEpisodeIDs = episodeIDs.filter { seen.insert($0).inserted }
      guard !uniqueEpisodeIDs.isEmpty else { return [] }

      let existingEpisodeIDs = Set(
        try EpisodeTranscriptionQueueEntry
          .filter(
            uniqueEpisodeIDs.contains(
              EpisodeTranscriptionQueueEntry.Columns.episodeId
            )
          )
          .select(
            EpisodeTranscriptionQueueEntry.Columns.episodeId,
            as: Episode.ID.self
          )
          .fetchAll(db)
      )
      let newEpisodeIDs = uniqueEpisodeIDs.filter {
        !existingEpisodeIDs.contains($0)
      }
      guard !newEpisodeIDs.isEmpty else { return [] }

      let currentCount = try EpisodeTranscriptionQueueEntry.fetchCount(db)
      guard currentCount + newEpisodeIDs.count <= maximumCount else {
        throw TranscriptionQueueError.capacityExceeded(
          limit: maximumCount,
          currentCount: currentCount,
          requestedCount: newEpisodeIDs.count
        )
      }

      for episodeID in newEpisodeIDs {
        try EpisodeTranscriptionQueueEntry(episodeId: episodeID).insert(db)
      }
      return newEpisodeIDs
    }
  }

  func remove(_ episodeID: Episode.ID) async throws {
    try await writer.write { db in
      try EpisodeTranscriptionQueueEntry
        .filter(EpisodeTranscriptionQueueEntry.Columns.episodeId == episodeID)
        .deleteAll(db)
    }
  }

  func reorder(_ orderedEpisodeIDs: [Episode.ID]) async throws -> Bool {
    try await writer.write { db in
      let currentEpisodeIDs = try Self.fetchAll(db)
      guard
        orderedEpisodeIDs.count == currentEpisodeIDs.count,
        Set(orderedEpisodeIDs) == Set(currentEpisodeIDs)
      else {
        return false
      }

      try EpisodeTranscriptionQueueEntry.deleteAll(db)
      for episodeID in orderedEpisodeIDs {
        try EpisodeTranscriptionQueueEntry(episodeId: episodeID).insert(db)
      }
      return true
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
