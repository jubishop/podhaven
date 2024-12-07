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
        t.column("feedURL", .text).unique().notNull().indexed()
        t.column("title", .text).notNull()
        t.column("link", .text)
        t.column("image", .text)
        t.column("description", .text)
      }
    }

    try migrator.migrate(db)
  }
}
