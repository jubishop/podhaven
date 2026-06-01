// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV38(_ db: Database) throws {
    try db.alter(table: "podcast") { t in
      t.add(column: "freshnessHalfLifeDays", .integer).check { $0 == nil || $0 >= 1 }
    }
  }
}
