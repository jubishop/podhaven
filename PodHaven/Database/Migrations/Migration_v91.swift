// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV91(_ db: Database) throws {
    try db.alter(table: "episodeEmbedding") { table in
      table.add(column: "recipeVersion", .integer).notNull().defaults(to: 2)
    }
  }
}
