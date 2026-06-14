// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV61(_ db: Database) throws {
    // User-selectable icon for tags and smart lists. Values are Lucide icon ids
    // that map to assets under Assets.xcassets/LucideIcons. The defaults backfill
    // existing rows so every tag and smart list always has an icon.
    try db.alter(table: "tag") { t in
      t.add(column: "icon", .text).notNull().defaults(to: "tag")
    }
    try db.alter(table: "smartList") { t in
      t.add(column: "icon", .text).notNull().defaults(to: "list-music")
    }
  }
}
