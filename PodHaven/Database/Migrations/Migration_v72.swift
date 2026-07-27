// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV72(_ db: Database) throws {
    // Per-list unread-badge visibility. The default preserves the existing
    // always-visible behavior and backfills every existing Smart List as enabled.
    try db.alter(table: "smartList") { t in
      t.add(column: "showUnreadBadge", .boolean).notNull().defaults(to: true)
    }
  }
}
