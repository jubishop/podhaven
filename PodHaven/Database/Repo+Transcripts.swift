// Copyright Justin Bishop, 2026

import GRDB
import Logging

private enum TranscriptStoreRequirement: Sendable {
  case none
  case publisherReferences([PublisherTranscriptReference])
  case publisherDemand([PublisherTranscriptReference])
}

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
      if transcript != nil {
        try PublisherTranscriptImportJob
          .filter(PublisherTranscriptImportJob.Columns.episodeId == episodeID)
          .deleteAll(db)
      }
      return updated > 0
    }
  }

  func storeTranscriptIfAbsent(
    _ episodeID: Episode.ID,
    transcript: Transcript,
    publisherSource: PublisherTranscriptReference?
  ) async throws -> Bool {
    try await storeTranscript(
      episodeID,
      transcript: transcript,
      publisherSource: publisherSource,
      requirement: .none
    )
  }

  func storePublisherTranscriptIfReferencesCurrent(
    _ episodeID: Episode.ID,
    imported: PublisherTranscriptImport,
    expectedReferences: [PublisherTranscriptReference]
  ) async throws -> Bool {
    try await storeTranscript(
      episodeID,
      transcript: imported.transcript,
      publisherSource: imported.source,
      requirement: .publisherReferences(expectedReferences)
    )
  }

  func storePublisherTranscriptIfDemandCurrent(
    _ episodeID: Episode.ID,
    imported: PublisherTranscriptImport,
    expectedReferences: [PublisherTranscriptReference]
  ) async throws -> Bool {
    try await storeTranscript(
      episodeID,
      transcript: imported.transcript,
      publisherSource: imported.source,
      requirement: .publisherDemand(expectedReferences)
    )
  }

  private func storeTranscript(
    _ episodeID: Episode.ID,
    transcript: Transcript,
    publisherSource: PublisherTranscriptReference?,
    requirement: TranscriptStoreRequirement
  ) async throws -> Bool {
    let transcriptJSON = try transcript.jsonString()
    let publisherSourceJSON = try PublisherTranscriptReference.jsonString(
      for: publisherSource
    )
    let requirementDescription =
      switch requirement {
      case .none:
        "none"
      case .publisherReferences(let references):
        "publisherReferences(\(references.count))"
      case .publisherDemand(let references):
        "publisherDemand(\(references.count))"
      }

    let stored = try await writer.write { db in
      switch requirement {
      case .none:
        break
      case .publisherReferences(let expectedReferences):
        guard
          let episode = try Episode.withID(episodeID).fetchOne(db),
          episode.publisherTranscriptReferences == expectedReferences
        else {
          return false
        }
      case .publisherDemand(let expectedReferences):
        guard
          let episode = try Episode.withID(episodeID).fetchOne(db),
          episode.publisherTranscriptReferences == expectedReferences,
          try PublisherTranscriptImportJob
            .filter(PublisherTranscriptImportJob.Columns.episodeId == episodeID)
            .fetchCount(db) > 0
        else {
          return false
        }
      }

      let updated =
        try Episode
        .withID(episodeID)
        .filter(Episode.Columns.transcript == nil)
        .updateAll(
          db,
          Episode.Columns.transcript.set(to: transcriptJSON),
          Episode.Columns.publisherTranscriptSourceJSON.set(to: publisherSourceJSON)
        )
      try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.episodeId == episodeID)
        .deleteAll(db)
      guard updated > 0 else { return false }
      try EpisodeTranscriptionCheckpoint
        .filter(EpisodeTranscriptionCheckpoint.Columns.episodeId == episodeID)
        .deleteAll(db)
      return true
    }
    Self.transcriptLog.debug(
      """
      storeTranscript: \(episodeID) chars=\(transcriptJSON.count) \
      requirement=\(requirementDescription) stored=\(stored)
      """
    )
    return stored
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
