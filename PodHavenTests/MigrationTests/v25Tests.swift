// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v25 migration tests", .container)
class V25MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("v25 migration adds partial index on queueOrder column")
  func testV25Migration() async throws {
    // Apply migrations up to v24
    try migrator.migrate(appDB.db, upTo: "v24")

    // Verify index doesn't exist yet
    try await appDB.db.read { db in
      let indexes = try Row.fetchAll(
        db,
        sql: "SELECT * FROM sqlite_master WHERE type = 'index' AND tbl_name = 'episode'"
      )
      let hasQueueOrderIndex = indexes.contains { row in
        (row["name"] as? String) == "episode_on_queueOrder"
      }
      #expect(!hasQueueOrderIndex, "queueOrder index should not exist before v25")
    }

    // Apply v25 migration
    try migrator.migrate(appDB.db, upTo: "v25")

    // Verify index exists after migration
    try await appDB.db.read { db in
      let indexes = try Row.fetchAll(
        db,
        sql: "SELECT * FROM sqlite_master WHERE type = 'index' AND tbl_name = 'episode'"
      )
      let queueOrderIndex = indexes.first { row in
        (row["name"] as? String) == "episode_on_queueOrder"
      }
      #expect(queueOrderIndex != nil, "queueOrder index should exist after v25")

      // Verify it's a partial index (sql contains WHERE clause)
      if let sql = queueOrderIndex?["sql"] as? String {
        #expect(
          sql.contains("WHERE"),
          "Index should be a partial index with a WHERE clause"
        )
      }
    }

    // Verify index is used for queue queries
    try await appDB.db.read { db in
      let plan = try Row.fetchAll(
        db,
        sql:
          "EXPLAIN QUERY PLAN SELECT * FROM episode WHERE queueOrder IS NOT NULL ORDER BY queueOrder"
      )
      let planDetail = plan.compactMap { $0["detail"] as? String }.joined(separator: " ")
      #expect(
        planDetail.contains("episode_on_queueOrder"),
        "Query should use the queueOrder index"
      )
    }
  }
}
