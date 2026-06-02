// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV21(_ db: Database) throws {
    try db.alter(table: "podcast") { t in
      t.add(column: "queueAllEpisodes", .text).notNull().defaults(to: "never")
    }
  }
}
