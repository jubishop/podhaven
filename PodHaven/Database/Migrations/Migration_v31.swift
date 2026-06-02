// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV31(_ db: Database) throws {
    try db.alter(table: "podcast") { t in
      t.add(column: "iTunesID", .integer)
    }
    try db.create(indexOn: "podcast", columns: ["iTunesID"], options: .unique)
  }
}
