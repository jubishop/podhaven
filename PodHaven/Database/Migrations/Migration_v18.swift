// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV18(_ db: Database) throws {
    try db.alter(table: "podcast") { t in
      t.add(column: "defaultPlaybackRate", .double).check { $0 >= 0.8 && $0 <= 2.0 }
    }
  }
}
