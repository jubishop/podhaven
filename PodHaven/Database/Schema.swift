// Copyright Justin Bishop, 2025

import Foundation
import GRDB

enum Schema {
  // MARK: - Columns

  static let id = Column("id")
  static let creationDate = Column("creationDate")

  // MARK: - Migrator

  static func makeMigrator() throws -> DatabaseMigrator {
    var migrator = DatabaseMigrator()

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
        t.column("lastUpdate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
        t.column("subscriptionDate", .datetime)
        t.column("cacheAllEpisodes", .boolean).notNull().defaults(to: false)
        t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
      }

      try db.create(table: "episode") { t in
        t.autoIncrementedPrimaryKey("id")
        t.uniqueKey(["podcastId", "guid"], onConflict: .fail)
        t.uniqueKey(["podcastId", "media"], onConflict: .fail)
        t.belongsTo("podcast", onDelete: .cascade).notNull()

        // Feed Info (Required)
        t.column("guid", .text).notNull().indexed()
        t.column("media", .text).notNull().indexed()
        t.column("title", .text).notNull()
        t.column("pubDate", .datetime).notNull()

        // Feed Info (Optional)
        t.column("duration", .integer)
        t.column("description", .text)
        t.column("link", .text)
        t.column("image", .text)

        // App Added Metadata
        t.column("completionDate", .datetime)
        t.column("currentTime", .integer).notNull().defaults(to: 0)
        t.column("queueOrder", .integer).check { $0 >= 0 }
        t.column("lastQueued", .datetime)
        t.column("cachedFilename", .text)
        t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
      }
    }

    migrator.registerMigration("v15") { db in
      // Add unique constraint on the combination of guid and media across all episodes
      // This ensures that the same episode (identified by guid + media URL) cannot exist
      // multiple times in the database, even across different podcasts

      // First, check for any existing duplicate combinations and handle them
      // This query finds episodes that have the same guid + media combination
      let duplicates = try Row.fetchAll(
        db,
        sql: """
          SELECT guid, media, COUNT(*) as count
          FROM episode 
          GROUP BY guid, media 
          HAVING COUNT(*) > 1
          """
      )

      if !duplicates.isEmpty {
        // If duplicates exist, keep only the oldest episode for each guid+media combination
        // and delete the newer ones (based on creationDate)
        try db.execute(
          sql: """
            DELETE FROM episode 
            WHERE id NOT IN (
              SELECT MIN(id) 
              FROM episode 
              GROUP BY guid, media
            )
            """
        )
      }

      // Now add the unique constraint on the combination of guid and media
      try db.execute(sql: "CREATE UNIQUE INDEX episode_on_guid_media ON episode(guid, media)")
    }

    return migrator
  }
}
