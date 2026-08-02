// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV81(_ db: Database) throws {
    try db.alter(table: "episodeTranscriptionQueue") { table in
      table.add(column: "workMode", .text)
        .notNull()
        .defaults(to: "publisherPreferred")
        .check(
          sql: "workMode IN ('publisherPreferred', 'onDeviceReplacement')"
        )
    }
  }
}
