// Copyright Justin Bishop, 2025

import Foundation
import GRDB

enum Schema {
  // MARK: - Episode Columns

  static let completedColumn = Column("completed")
  static let currentTimeColumn = Column("currentTime")
  static let lastUpdateColumn = Column("lastUpdate")
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

        // Feed Info (Required)
        t.column("feedURL", .text).unique(onConflict: .fail).notNull().indexed()
        t.column("title", .text).notNull()
        t.column("image", .text).notNull()
        t.column("description", .text).notNull()

        // Feed Info (Optional)
        t.column("link", .text)

        // App Added Metadata
        t.column("lastUpdate", .datetime).defaults(to: Date())
        t.column("subscribed", .boolean).notNull()
      }

      try db.create(table: "episode") { t in
        t.autoIncrementedPrimaryKey("id")
        t.uniqueKey(["podcastId", "guid"], onConflict: .fail)
        t.belongsTo("podcast", onDelete: .cascade).notNull()

        // Feed Info (Required)
        t.column("guid", .text).notNull().indexed()
        t.column("media", .text).unique(onConflict: .fail).notNull().indexed()
        t.column("title", .text).notNull()
        t.column("pubDate", .datetime).notNull()

        // Feed Info (Optional)
        t.column("duration", .integer)
        t.column("description", .text)
        t.column("link", .text)
        t.column("image", .text)

        // App Added Metadata
        t.column("completed", .boolean).defaults(to: false)
        t.column("currentTime", .integer).defaults(to: 0)
        t.column("queueOrder", .integer).check { $0 >= 0 }
      }
    }

    return migrator
  }
}
