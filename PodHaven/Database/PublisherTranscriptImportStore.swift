// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB

extension Container {
  var publisherTranscriptImportStore: Factory<PublisherTranscriptImportStore> {
    Factory(self) {
      let appDB = self.appDB()
      return PublisherTranscriptImportStore(
        reader: appDB.reader,
        writer: appDB.writer
      )
    }
    .scope(.cached)
  }
}

struct PublisherTranscriptImportStore: Sendable {
  static let maximumAttemptCount = 3

  enum RetryResult: Sendable {
    case exhausted(attemptCount: Int)
    case resolved
    case retained(attemptCount: Int)
    case superseded
  }

  private let reader: AppDB.Reader
  private let writer: AppDB.Writer

  fileprivate init(reader: AppDB.Reader, writer: AppDB.Writer) {
    self.reader = reader
    self.writer = writer
  }

  static func insert(
    _ episodeID: Episode.ID,
    nextAttemptAt: Date,
    in db: Database
  ) throws {
    try PublisherTranscriptImportJob(
      episodeId: episodeID,
      nextAttemptAt: nextAttemptAt
    )
    .insert(db, onConflict: .ignore)
  }

  func eligibleJobs(at date: Date, limit: Int) async throws
    -> [PublisherTranscriptImportJob]
  {
    try await reader.read { db in
      try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.nextAttemptAt <= date)
        .order(
          PublisherTranscriptImportJob.Columns.nextAttemptAt,
          PublisherTranscriptImportJob.Columns.episodeId
        )
        .limit(limit)
        .fetchAll(db)
    }
  }

  func hasEligibleWork(at date: Date) async throws -> Bool {
    try await reader.read { db in
      try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.nextAttemptAt <= date)
        .fetchCount(db) > 0
    }
  }

  func hasWork() async throws -> Bool {
    try await reader.read { db in
      try PublisherTranscriptImportJob.fetchCount(db) > 0
    }
  }

  func remove(_ episodeID: Episode.ID) async throws {
    try await writer.write { db in
      try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.episodeId == episodeID)
        .deleteAll(db)
    }
  }

  @discardableResult
  func remove(
    _ job: PublisherTranscriptImportJob,
    ifReferencesMatch expectedReferences: [PublisherTranscriptReference]
  ) async throws -> Bool {
    try await writer.write { db in
      guard
        try Self.references(
          for: job.episodeId,
          match: expectedReferences,
          in: db
        )
      else {
        return false
      }
      return try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.episodeId == job.episodeId)
        .deleteAll(db) > 0
    }
  }

  func recordRetry(
    for job: PublisherTranscriptImportJob,
    at date: Date,
    ifReferencesMatch expectedReferences: [PublisherTranscriptReference]
  ) async throws -> RetryResult {
    try await writer.write { db in
      guard
        try Self.references(
          for: job.episodeId,
          match: expectedReferences,
          in: db
        )
      else {
        return .superseded
      }
      guard
        let currentJob =
          try PublisherTranscriptImportJob
          .filter(PublisherTranscriptImportJob.Columns.episodeId == job.episodeId)
          .fetchOne(db)
      else {
        return .resolved
      }

      let attemptCount = currentJob.attemptCount + 1
      guard attemptCount < Self.maximumAttemptCount else {
        try PublisherTranscriptImportJob
          .filter(PublisherTranscriptImportJob.Columns.episodeId == job.episodeId)
          .deleteAll(db)
        return .exhausted(attemptCount: attemptCount)
      }

      let delay: Duration = attemptCount == 1 ? .minutes(1) : .minutes(5)
      let nextAttemptAt = date.advanced(by: delay.asTimeInterval)
      let updated =
        try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.episodeId == job.episodeId)
        .updateAll(
          db,
          PublisherTranscriptImportJob.Columns.attemptCount.set(to: attemptCount),
          PublisherTranscriptImportJob.Columns.nextAttemptAt.set(to: nextAttemptAt)
        )
      return updated > 0
        ? .retained(attemptCount: attemptCount)
        : .resolved
    }
  }

  private static func references(
    for episodeID: Episode.ID,
    match expectedReferences: [PublisherTranscriptReference],
    in db: Database
  ) throws -> Bool {
    guard let episode = try Episode.withID(episodeID).fetchOne(db) else {
      return false
    }
    return episode.publisherTranscriptReferences == expectedReferences
  }
}
