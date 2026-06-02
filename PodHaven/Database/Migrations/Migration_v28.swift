// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV28(_ db: Database) throws {
    try db.create(table: "episodeTag") { t in
      t.belongsTo("episode", onDelete: .cascade).notNull()
      t.belongsTo("tag", onDelete: .cascade).notNull()
      t.uniqueKey(["episodeId", "tagId"], onConflict: .fail)
    }
  }
}
