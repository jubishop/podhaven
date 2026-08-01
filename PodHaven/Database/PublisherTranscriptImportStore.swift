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
  func recordRetry(
    for job: PublisherTranscriptImportJob,
    at date: Date
  ) async throws -> Bool {
    let attemptCount = job.attemptCount + 1
    guard attemptCount < Self.maximumAttemptCount else {
      try await remove(job.episodeId)
      return false
    }

    let delay: Duration = attemptCount == 1 ? .minutes(1) : .minutes(5)
    let nextAttemptAt = date.advanced(by: delay.asTimeInterval)
    return try await writer.write { db in
      try PublisherTranscriptImportJob
        .filter(PublisherTranscriptImportJob.Columns.episodeId == job.episodeId)
        .updateAll(
          db,
          PublisherTranscriptImportJob.Columns.attemptCount.set(to: attemptCount),
          PublisherTranscriptImportJob.Columns.nextAttemptAt.set(to: nextAttemptAt)
        ) > 0
    }
  }
}
