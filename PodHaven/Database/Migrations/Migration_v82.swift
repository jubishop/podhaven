// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV82(_ db: Database) throws {
    try db.alter(table: "podcast") { table in
      table.add(column: "silenceMode", .text)
        .check(sql: "silenceMode IN ('off', 'gentle', 'balanced', 'aggressive')")
    }
    try db.create(table: "cachedAudioContent") { table in
      table.column("filename", .text).primaryKey()
      table.column("generation", .text).notNull().unique()
      table.column("detectorVersion", .integer)
      table.column("analysis", .blob)
      table.column("failureCount", .integer).notNull().defaults(to: 0)
    }
  }
}
