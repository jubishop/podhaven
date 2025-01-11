// Copyright Justin Bishop, 2025

import Foundation
import GRDB

enum Schema {
  // MARK: - Episode Columns

  static let completedColumn = Column("completed")
  static let currentTimeColumn = Column("currentTime")
  static let mediaColumn = Column("media")
  static let pubDateColumn = Column("pubDate")
  static let queueOrderColumn = Column("queueOrder")

  // MARK: - Migrator

  static func makeMigrator() throws -> DatabaseMigrator {
    var migrator = DatabaseMigrator()

    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1") { db in
      try db.create(table: "podcast") { t in
        t.autoIncrementedPrimaryKey("id")
        t
          .column("feedURL", .text)
          .unique(onConflict: .fail)
          .notNull()
          .indexed()
        t.column("title", .text).notNull()
        t.column("link", .text)
        t.column("image", .text).notNull()
        t.column("description", .text).notNull()
        t.column("lastUpdate", .integer).notNull()
      }

      try db.create(table: "episode") { t in
        t.autoIncrementedPrimaryKey("id")
        t.belongsTo("podcast", onDelete: .cascade).notNull()
        t.column("guid", .text).notNull().indexed()
        t.uniqueKey(["podcastId", "guid"], onConflict: .fail)
        t
          .column("media", .text)
          .unique(onConflict: .fail)
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

    return migrator
  }
}
