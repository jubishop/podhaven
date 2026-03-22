// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v32 migration tests", .container)
class V32MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Helpers

  private func insertPodcast(_ db: Database) throws -> Int64 {
    try db.execute(
      sql: """
        INSERT INTO podcast (feedURL, title, image, description)
        VALUES ('https://example.com/feed.xml', 'Test', 'img', 'desc')
        """
    )
    return db.lastInsertedRowID
  }

  private func insertEpisode(
    _ db: Database,
    podcastID: Int64,
    guid: String,
    queueOrder: Int?
  ) throws -> Int64 {
    try db.execute(
      sql: """
        INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, queueOrder)
        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
        """,
      arguments: [podcastID, guid, "https://example.com/\(guid).mp3", guid, queueOrder]
    )
    return db.lastInsertedRowID
  }

  private func fetchQueueOrders(_ db: Database) throws -> [Int64: Int?] {
    let rows = try Row.fetchAll(db, sql: "SELECT id, queueOrder FROM episode ORDER BY id")
    var result: [Int64: Int?] = [:]
    for row in rows {
      let id: Int64 = row["id"]
      let order: Int? = row["queueOrder"]
      result[id] = order
    }
    return result
  }

  // MARK: - Tests

  @Test("trims episodes beyond position 100")
  func testTrimsBeyond100() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")

    try await appDB.db.write { [weak self] db in
      guard let self else { return }
      let podcastID = try insertPodcast(db)

      // Insert 120 queued episodes with dense 0-based queueOrder
      for i in 0..<120 {
        _ = try insertEpisode(db, podcastID: podcastID, guid: "ep-\(i)", queueOrder: i)
      }
    }

    try migrator.migrate(appDB.db, upTo: "v32")

    try await appDB.db.read { db in
      let queuedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NOT NULL"
      )
      #expect(queuedCount == 100)

      // Episodes 0-99 should still be queued
      let maxOrder = try Int.fetchOne(
        db,
        sql: "SELECT MAX(queueOrder) FROM episode WHERE queueOrder IS NOT NULL"
      )
      #expect(maxOrder == 99)

      // Episodes that had queueOrder >= 100 should be nulled
      let nulledCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NULL"
      )
      #expect(nulledCount == 20)
    }
  }

  @Test("does not trim when queue has exactly 100 episodes")
  func testExactly100() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")

    try await appDB.db.write { [weak self] db in
      guard let self else { return }
      let podcastID = try insertPodcast(db)

      for i in 0..<100 {
        _ = try insertEpisode(db, podcastID: podcastID, guid: "ep-\(i)", queueOrder: i)
      }
    }

    try migrator.migrate(appDB.db, upTo: "v32")

    try await appDB.db.read { db in
      let queuedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NOT NULL"
      )
      #expect(queuedCount == 100)

      let nulledCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NULL"
      )
      #expect(nulledCount == 0)
    }
  }

  @Test("does not trim when queue is under 100 episodes")
  func testUnder100() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")

    try await appDB.db.write { [weak self] db in
      guard let self else { return }
      let podcastID = try insertPodcast(db)

      for i in 0..<50 {
        _ = try insertEpisode(db, podcastID: podcastID, guid: "ep-\(i)", queueOrder: i)
      }
    }

    try migrator.migrate(appDB.db, upTo: "v32")

    try await appDB.db.read { db in
      let queuedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NOT NULL"
      )
      #expect(queuedCount == 50)
    }
  }

  @Test("does not affect unqueued episodes")
  func testUnqueuedUntouched() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")

    try await appDB.db.write { [weak self] db in
      guard let self else { return }
      let podcastID = try insertPodcast(db)

      // 110 queued + 5 unqueued
      for i in 0..<110 {
        _ = try insertEpisode(db, podcastID: podcastID, guid: "ep-\(i)", queueOrder: i)
      }
      for i in 0..<5 {
        _ = try insertEpisode(db, podcastID: podcastID, guid: "unqueued-\(i)", queueOrder: nil)
      }
    }

    try migrator.migrate(appDB.db, upTo: "v32")

    try await appDB.db.read { db in
      let queuedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NOT NULL"
      )
      #expect(queuedCount == 100)

      // 10 trimmed + 5 originally unqueued = 15 with NULL queueOrder
      let nulledCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NULL"
      )
      #expect(nulledCount == 15)
    }
  }

  @Test("handles empty queue")
  func testEmptyQueue() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")

    try await appDB.db.write { [weak self] db in
      guard let self else { return }
      let podcastID = try insertPodcast(db)

      // Only unqueued episodes
      for i in 0..<3 {
        _ = try insertEpisode(db, podcastID: podcastID, guid: "ep-\(i)", queueOrder: nil)
      }
    }

    try migrator.migrate(appDB.db, upTo: "v32")

    try await appDB.db.read { db in
      let queuedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NOT NULL"
      )
      #expect(queuedCount == 0)

      let totalCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode"
      )
      #expect(totalCount == 3)
    }
  }
}
