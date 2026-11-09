// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v88 migration tests", .container)
struct V88MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v88 clears recorded silence analysis failures and keeps published analysis")
  func clearsFailures() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v87")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO cachedAudioContent (filename, generation, detectorVersion, analysis, failureCount)
          VALUES
            ('failed.mp3', 'failed', 2, NULL, 2),
            ('retrying.mp3', 'retrying', 2, NULL, 1),
            ('analyzed.mp3', 'analyzed', 2, X'7B7D', 0)
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB)

    try await appDB.unsafeTestDB.write { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT filename, generation, detectorVersion, analysis, failureCount
          FROM cachedAudioContent ORDER BY filename
          """
      )
      #expect(
        rows.map { $0["filename"] as String } == ["analyzed.mp3", "failed.mp3", "retrying.mp3"]
      )
      #expect(rows.map { $0["generation"] as String } == ["analyzed", "failed", "retrying"])
      #expect(rows.map { $0["detectorVersion"] as Int } == [2, 2, 2])
      #expect(rows.map { $0["failureCount"] as Int } == [0, 0, 0])
      #expect(rows.map { $0["analysis"] as Data? } == [Data("{}".utf8), nil, nil])
    }
  }
}
