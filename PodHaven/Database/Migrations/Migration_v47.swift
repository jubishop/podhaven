// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV47(_ db: Database) throws {
    try db.alter(table: "podcast") { t in
      t.add(column: "autoQueueLimit", .integer).check { $0 == nil || ($0 >= 1 && $0 <= 5) }
    }
  }
}
