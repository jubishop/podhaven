// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV79(_ db: Database) throws {
    try db.alter(table: "episode") { table in
      table.add(column: "publisherTranscriptReferencesJSON", .text)
      table.add(column: "publisherTranscriptSourceJSON", .text)
    }
  }
}
