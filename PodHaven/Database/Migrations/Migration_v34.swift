// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV34(_ db: Database) throws {
    try db.alter(table: "episode") { t in
      t.add(column: "maxPlaybackTime", .integer).notNull().defaults(to: 0)
    }
    // Seed from existing progress so in-progress episodes start at their
    // furthest-reached point. Finished episodes have currentTime = 0, so
    // they correctly start at 0.
    try db.execute(sql: "UPDATE episode SET maxPlaybackTime = currentTime")
  }
}
