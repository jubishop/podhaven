// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV86(_ db: Database) throws {
    try db.alter(table: "podcast") { table in
      table.add(column: "feedETag", .text)
      table.add(column: "feedLastModified", .text)
      table.add(column: "feedValidatorsBuild", .text)
    }
  }
}
