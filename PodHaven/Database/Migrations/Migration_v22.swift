// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV22(_ db: Database) throws {
    try db.alter(table: "episode") { t in
      t.add(column: "saveInCache", .boolean).notNull().defaults(to: false)
    }
  }
}
