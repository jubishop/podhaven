// Copyright Justin Bishop, 2026

import FactoryKit
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

  private var defaults: FakeKeyValueStore {
    Container.shared.standardDefaults() as! FakeKeyValueStore
  }

  // MARK: - Helpers

  private func seedMaxQueueLength(_ value: Int) throws {
    let data = try JSONEncoder().encode(value)
    defaults.set(data, forKey: "maxQueueLength")
  }

  private func loadMaxQueueLength() throws -> Int? {
    guard let data = defaults.data(forKey: "maxQueueLength") else { return nil }
    return try JSONDecoder().decode(Int.self, from: data)
  }

  private static func insertPodcast(_ db: Database) throws -> Int64 {
    try db.execute(
      sql: """
        INSERT INTO podcast (feedURL, title, image, description)
        VALUES ('https://example.com/feed.xml', 'Test', 'img', 'desc')
        """
    )
    return db.lastInsertedRowID
  }

  private static func insertEpisodes(
    _ db: Database,
    podcastID: Int64,
    queuedCount: Int,
    unqueuedCount: Int = 0
  ) throws {
    for i in 0..<queuedCount {
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, queueOrder)
          VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
          """,
        arguments: [podcastID, "ep-\(i)", "https://example.com/ep-\(i).mp3", "ep-\(i)", i]
      )
    }
    for i in 0..<unqueuedCount {
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, queueOrder)
          VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, NULL)
          """,
        arguments: [
          podcastID, "unqueued-\(i)", "https://example.com/unqueued-\(i).mp3", "unqueued-\(i)",
        ]
      )
    }
  }

  // MARK: - Tests

  @Test("trims episodes beyond position 100")
  func testTrimsBeyond100() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")

    try await appDB.db.write { db in
      let podcastID = try V32MigrationTests.insertPodcast(db)
      try V32MigrationTests.insertEpisodes(db, podcastID: podcastID, queuedCount: 120)
    }

    try migrator.migrate(appDB.db, upTo: "v32")

    try await appDB.db.read { db in
      let queuedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NOT NULL"
      )
      #expect(queuedCount == 100)

      let maxOrder = try Int.fetchOne(
        db,
        sql: "SELECT MAX(queueOrder) FROM episode WHERE queueOrder IS NOT NULL"
      )
      #expect(maxOrder == 99)

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

    try await appDB.db.write { db in
      let podcastID = try V32MigrationTests.insertPodcast(db)
      try V32MigrationTests.insertEpisodes(db, podcastID: podcastID, queuedCount: 100)
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

    try await appDB.db.write { db in
      let podcastID = try V32MigrationTests.insertPodcast(db)
      try V32MigrationTests.insertEpisodes(db, podcastID: podcastID, queuedCount: 50)
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

    try await appDB.db.write { db in
      let podcastID = try V32MigrationTests.insertPodcast(db)
      try V32MigrationTests.insertEpisodes(
        db,
        podcastID: podcastID,
        queuedCount: 110,
        unqueuedCount: 5
      )
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

    try await appDB.db.write { db in
      let podcastID = try V32MigrationTests.insertPodcast(db)
      try V32MigrationTests.insertEpisodes(
        db,
        podcastID: podcastID,
        queuedCount: 0,
        unqueuedCount: 3
      )
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

  // MARK: - UserDefaults Clamping

  @Test("clamps maxQueueLength from above 100 to 100")
  func testClampsAbove100() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")
    try seedMaxQueueLength(500)

    try migrator.migrate(appDB.db, upTo: "v32")

    #expect(try loadMaxQueueLength() == 100)
  }

  @Test("does not clamp maxQueueLength at exactly 100")
  func testDoesNotClampAt100() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")
    try seedMaxQueueLength(100)

    try migrator.migrate(appDB.db, upTo: "v32")

    #expect(try loadMaxQueueLength() == 100)
  }

  @Test("does not clamp maxQueueLength below 100")
  func testDoesNotClampBelow100() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")
    try seedMaxQueueLength(50)

    try migrator.migrate(appDB.db, upTo: "v32")

    #expect(try loadMaxQueueLength() == 50)
  }

  @Test("handles missing maxQueueLength in defaults")
  func testMissingMaxQueueLength() async throws {
    try migrator.migrate(appDB.db, upTo: "v31")

    try migrator.migrate(appDB.db, upTo: "v32")

    #expect(try loadMaxQueueLength() == nil)
  }
}
