// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV41(_ db: Database) throws {
    try db.alter(table: "episode") { t in
      t.add(column: "playbackCoverage", .blob)
      t.add(column: "lastPlayedDate", .datetime)
    }
  }
}
