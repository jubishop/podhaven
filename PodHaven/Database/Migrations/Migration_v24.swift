// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV24(_ db: Database) throws {
    try db.alter(table: "podcast") { t in
      t.add(column: "notifyNewEpisodes", .boolean).notNull().defaults(to: false)
    }
  }
}
