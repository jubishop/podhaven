// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV83(_ db: Database) throws {
    try db.alter(table: "podcast") { table in
      table.add(column: "quietAudioProtection", .text)
        .check(sql: "quietAudioProtection IN ('high', 'medium', 'low')")
    }
    try db.execute(
      sql: "UPDATE cachedAudioContent SET analysis = NULL, detectorVersion = 2, failureCount = 0"
    )
  }
}
