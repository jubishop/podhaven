// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v88 migration tests", .container)
struct V88MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v88 starts existing podcasts with no refresh failures or backoff")
  func addsRefreshBackoffColumns() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v87")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (id, feedURL, title, image, description)
          VALUES (
            880, 'https://example.com/v88.xml', 'Backoff Show',
            'https://example.com/v88.jpg', 'Description'
          )
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB)

    try await appDB.unsafeTestDB.write { db in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: "SELECT refreshFailureCount, refreshBackoffUntil FROM podcast WHERE id = 880"
        )
      )
      #expect(row["refreshFailureCount"] as Int? == 0)
      #expect(row["refreshBackoffUntil"] as Date? == nil)

      try db.execute(
        sql: """
          INSERT INTO podcast (id, feedURL, title, image, description)
          VALUES (
            881, 'https://example.com/v88-new.xml', 'New Show',
            'https://example.com/v88-new.jpg', 'Description'
          )
          """
      )
      #expect(
        try Int.fetchOne(db, sql: "SELECT refreshFailureCount FROM podcast WHERE id = 881") == 0
      )
      #expect(
        throws: DatabaseError.self,
        performing: {
          try db.execute(sql: "UPDATE podcast SET refreshFailureCount = NULL WHERE id = 881")
        }
      )
    }
  }
}
