// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV89(_ db: Database) throws {
    try db.alter(table: "podcast") { table in
      table.add(column: "refreshFailureCount", .integer).notNull().defaults(to: 0)
      table.add(column: "refreshBackoffUntil", .datetime)
    }
  }
}
