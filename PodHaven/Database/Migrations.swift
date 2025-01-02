// Copyright Justin Bishop, 2024

import Foundation
import GRDB

enum Migrations {
  static func migrate(_ db: DatabaseWriter) throws {
    var migrator = DatabaseMigrator()

    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1") { db in
      try db.create(table: "podcast") { t in
        t.autoIncrementedPrimaryKey("id")
        t
          .column("feedURL", .text)
          .unique(onConflict: .replace)
          .notNull()
          .indexed()
        t.column("title", .text).notNull()
        t.column("link", .text).notNull()
        t.column("image", .text).notNull()
        t.column("description", .text).notNull()
        t.column("lastUpdate", .integer).notNull()
      }

      try db.create(table: "episode") { t in
        t.autoIncrementedPrimaryKey("id")
        t.belongsTo("podcast", onDelete: .cascade).notNull()
        t.column("guid", .text).notNull().indexed()
        t.uniqueKey(["podcastId", "guid"], onConflict: .replace)
        t
          .column("media", .text)
          .unique(onConflict: .replace)
          .notNull()
          .indexed()
        t.column("title", .text).notNull()
        t.column("currentTime", .integer)
        t.column("completed", .boolean).defaults(to: false)
        t.column("duration", .integer)
        t.column("pubDate", .text).notNull()
        t.column("description", .text)
        t.column("link", .text)
        t.column("image", .text)
        t.column("queueOrder", .integer).check { $0 >= 0 }
      }
    }

    try migrator.migrate(db)
  }
}
