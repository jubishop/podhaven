// Copyright Justin Bishop, 2026

import GRDB
import Logging

extension Repo {
  private static var transcriptLog: Logger {
    Log.as(LogSubsystem.Database.repo)
  }

  @discardableResult
  func updateTranscript(_ episodeID: Episode.ID, transcript: String?) async throws -> Bool {
    Self.transcriptLog.debug(
      "updateTranscript: \(episodeID) to \(transcript?.count ?? 0) chars"
    )

    return try await writer.write { db in
      let updated =
        try Episode
        .withID(episodeID)
        .updateAll(
          db,
          Episode.Columns.transcript.set(to: transcript),
          Episode.Columns.publisherTranscriptSourceJSON.set(to: nil)
        )
      try EpisodeTranscriptionCheckpoint
        .filter(EpisodeTranscriptionCheckpoint.Columns.episodeId == episodeID)
        .deleteAll(db)
      return updated > 0
    }
  }

  func storeTranscriptIfAbsent(
    _ episodeID: Episode.ID,
    transcript: Transcript,
    publisherSource: PublisherTranscriptReference?
  ) async throws -> Bool {
    let transcriptJSON = try transcript.jsonString()
    let publisherSourceJSON = try PublisherTranscriptReference.jsonString(
      for: publisherSource
    )
    Self.transcriptLog.debug(
      "storeTranscriptIfAbsent: \(episodeID) to \(transcriptJSON.count) chars"
    )

    return try await writer.write { db in
      let updated =
        try Episode
        .withID(episodeID)
        .filter(Episode.Columns.transcript == nil)
        .updateAll(
          db,
          Episode.Columns.transcript.set(to: transcriptJSON),
          Episode.Columns.publisherTranscriptSourceJSON.set(to: publisherSourceJSON)
        )
      guard updated > 0 else { return false }
      try EpisodeTranscriptionCheckpoint
        .filter(EpisodeTranscriptionCheckpoint.Columns.episodeId == episodeID)
        .deleteAll(db)
      return true
    }
  }

  func replacePublisherTranscript(
    _ episodeID: Episode.ID,
    with transcript: Transcript
  ) async throws -> Bool {
    let transcriptJSON = try transcript.jsonString()
    Self.transcriptLog.debug(
      "replacePublisherTranscript: \(episodeID) to \(transcriptJSON.count) chars"
    )

    return try await writer.write { db in
      guard
        let queuedWork =
          try EpisodeTranscriptionQueueEntry
          .filter(EpisodeTranscriptionQueueEntry.Columns.episodeId == episodeID)
          .fetchOne(db),
        queuedWork.workMode == .onDeviceReplacement
      else {
        return false
      }

      let updated =
        try Episode
        .withID(episodeID)
        .filter(Episode.Columns.transcript != nil)
        .filter(Episode.Columns.publisherTranscriptSourceJSON != nil)
        .updateAll(
          db,
          Episode.Columns.transcript.set(to: transcriptJSON),
          Episode.Columns.publisherTranscriptSourceJSON.set(to: nil)
        )
      guard updated > 0 else { return false }

      try EpisodeTranscriptionCheckpoint
        .filter(EpisodeTranscriptionCheckpoint.Columns.episodeId == episodeID)
        .deleteAll(db)
      try EpisodeTranscriptionQueueEntry
        .filter(EpisodeTranscriptionQueueEntry.Columns.episodeId == episodeID)
        .filter(
          EpisodeTranscriptionQueueEntry.Columns.workMode
            == TranscriptionWorkMode.onDeviceReplacement
        )
        .deleteAll(db)
      return true
    }
  }

  func saveTranscriptionCheckpoint(
    _ checkpoint: TranscriptionCheckpoint,
    for episodeID: Episode.ID
  ) async throws {
    let stored = try EpisodeTranscriptionCheckpoint(
      episodeId: episodeID,
      checkpoint: checkpoint
    )
    try await writer.write { db in
      try stored.save(db)
    }
  }

  func deleteTranscriptionCheckpoint(for episodeID: Episode.ID) async throws {
    try await writer.write { db in
      try EpisodeTranscriptionCheckpoint
        .filter(EpisodeTranscriptionCheckpoint.Columns.episodeId == episodeID)
        .deleteAll(db)
    }
  }
}
