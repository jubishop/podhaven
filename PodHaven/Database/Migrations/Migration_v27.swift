// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV27(_ db: Database) throws {
    try db.create(table: "tag") { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("name", .text).notNull().collate(.nocase).unique(onConflict: .fail)
      t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    }

    try db.create(table: "podcastTag") { t in
      t.belongsTo("podcast", onDelete: .cascade).notNull()
      t.belongsTo("tag", onDelete: .cascade).notNull()
      t.uniqueKey(["podcastId", "tagId"], onConflict: .fail)
    }
  }
}
