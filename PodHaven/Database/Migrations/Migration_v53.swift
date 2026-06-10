// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV53(_ db: Database) throws {
    // Boundary-flipped mirror of `currentTime > 0`. Candidate/started filters
    // read this flag instead of currentTime, keeping per-checkpoint playback
    // writes out of their observations' tracked regions.
    try db.alter(table: "episode") { t in
      t.add(column: "playbackStarted", .boolean).notNull().defaults(to: false)
    }
    try db.execute(sql: "UPDATE episode SET playbackStarted = 1 WHERE currentTime > 0")
  }
}
