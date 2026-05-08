// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v43 migration tests", .container)
class V43MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  private func populateAtV42() async throws {
    try migrator.migrate(appDB.db, upTo: "v42")

    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            feedURL, title, image, description, contentUpdatedAt
          ) VALUES (
            'https://example.com/v43.xml', 'V43 Podcast',
            'https://example.com/img.jpg', 'Description',
            '2024-01-01 00:00:00'
          )
          """
      )
      let podcastID = db.lastInsertedRowID
      for i in 0..<10 {
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate
            ) VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            podcastID,
            "guid-\(i)",
            "https://example.com/ep-\(i).mp3",
            "Episode \(i)",
            "2024-01-\(String(format: "%02d", i + 1)) 00:00:00",
          ]
        )
      }
    }
  }

  // MARK: - Index Existence

  @Test("v43 creates an index named episode_on_pubDate on episode(pubDate)")
  func indexExists() async throws {
    try await populateAtV42()

    let indexBeforeV43 = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: """
          SELECT sql FROM sqlite_master
          WHERE type = 'index' AND name = 'episode_on_pubDate'
          """
      )
    }
    #expect(indexBeforeV43 == nil)

    try migrator.migrate(appDB.db, upTo: "v43")

    let indexAfterV43 = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: """
          SELECT sql FROM sqlite_master
          WHERE type = 'index' AND name = 'episode_on_pubDate'
          """
      )
    }
    #expect(indexAfterV43?.contains("\"episode\"") == true)
    #expect(indexAfterV43?.contains("\"pubDate\"") == true)
  }

  // MARK: - Plan Uses Index

  // The whole point of v43: ORDER BY pubDate DESC LIMIT 100 (the
  // EpisodesView default sort) should plan against the new index instead
  // of materialising a TEMP B-TREE over the entire episode table.
  @Test("ORDER BY pubDate DESC LIMIT 100 plans against episode_on_pubDate after v43")
  func orderByPubDateUsesIndex() async throws {
    try await populateAtV42()

    let planBefore = try await appDB.db.read { db in
      try Row.fetchAll(
        db,
        sql: """
          EXPLAIN QUERY PLAN
            SELECT id FROM episode ORDER BY pubDate DESC LIMIT 100
          """
      )
      .map { $0["detail"] as String }
      .joined(separator: "\n")
    }
    #expect(planBefore.contains("USE TEMP B-TREE FOR ORDER BY"))

    try migrator.migrate(appDB.db, upTo: "v43")

    let planAfter = try await appDB.db.read { db in
      try Row.fetchAll(
        db,
        sql: """
          EXPLAIN QUERY PLAN
            SELECT id FROM episode ORDER BY pubDate DESC LIMIT 100
          """
      )
      .map { $0["detail"] as String }
      .joined(separator: "\n")
    }
    #expect(planAfter.contains("episode_on_pubDate"))
    #expect(!planAfter.contains("USE TEMP B-TREE FOR ORDER BY"))
  }

  // MARK: - Data Preservation

  // Defensive: an index migration shouldn't touch row contents, but rebuilds
  // have shipped at v37/v42 so confirm v43 is the cheap shape we intend.
  @Test("episode rows unchanged across v43 migration")
  func episodeRowsPreserved() async throws {
    try await populateAtV42()

    let before = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM episode ORDER BY id")
        .map { $0.asDictionary() }
    }

    try migrator.migrate(appDB.db, upTo: "v43")

    let after = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM episode ORDER BY id")
        .map { $0.asDictionary() }
    }
    #expect(before == after)
  }
}

extension Row {
  fileprivate func asDictionary() -> [String: DatabaseValue] {
    var result: [String: DatabaseValue] = [:]
    for name in columnNames {
      let value: DatabaseValue = self[name]
      result[name] = value
    }
    return result
  }
}
