// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV61(_ db: Database) throws {
    // Unread-badge watermark: the highest episode id a Smart List has "seen".
    // Counting matching episodes with a greater id gives the unread count
    // without loading the list. Backfilling to the current top id starts every
    // existing list fully seen (badge 0) on upgrade; an empty library has no
    // episodes, so the watermark is 0 and the first synced episodes (ids start
    // at 1) all count as new.
    try db.alter(table: "smartList") { t in
      t.add(column: "lastSeenEpisodeId", .integer).notNull().defaults(to: 0)
    }
    try db.execute(
      sql: "UPDATE smartList SET lastSeenEpisodeId = COALESCE((SELECT MAX(id) FROM episode), 0)"
    )
  }
}
