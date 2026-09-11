// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v82 migration tests", .container)
struct V82MigrationTests {
  @Test("podcasts can inherit or explicitly disable silence shortening")
  func nullableSilenceMode() async throws {
    let appDB = AppDB.inMemory(migrate: false)
    let migrator = Schema.makeMigrator()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v81")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (id, feedURL, title, image, description)
          VALUES (820, 'https://example.com/v82.xml', 'Silence',
                  'https://example.com/v82.jpg', 'Description')
          """
      )
    }
    try migrator.migrate(appDB.unsafeTestDB)
    let columns = try await appDB.unsafeTestDB.read { db in
      try db.columns(in: "podcast").map(\.name)
    }
    #expect(columns.contains("silenceMode"))
    guard columns.contains("silenceMode") else { return }
    try await appDB.unsafeTestDB.write { db in
      #expect(try String.fetchOne(db, sql: "SELECT silenceMode FROM podcast WHERE id = 820") == nil)
      for mode in ["off", "gentle", "balanced", "aggressive"] {
        try db.execute(sql: "UPDATE podcast SET silenceMode = ? WHERE id = 820", arguments: [mode])
        #expect(
          try String.fetchOne(db, sql: "SELECT silenceMode FROM podcast WHERE id = 820") == mode
        )
      }
      #expect(throws: DatabaseError.self) {
        try db.execute(sql: "UPDATE podcast SET silenceMode = 'custom' WHERE id = 820")
      }
      try db.execute(sql: "UPDATE podcast SET silenceMode = NULL WHERE id = 820")
      #expect(try String.fetchOne(db, sql: "SELECT silenceMode FROM podcast WHERE id = 820") == nil)
    }
  }
}
