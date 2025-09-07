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

    // v16: Add nullable downloadTaskID to episode and unique index on it
    migrator.registerMigration("v16") { db in
      try db.alter(table: "episode") { t in
        t.add(column: "downloadTaskID", .integer)
      }

      // Unique index bothenforces one-to-one mapping and provides an index for lookups
      try db.execute(
        sql: "CREATE UNIQUE INDEX episode_on_downloadTaskID ON episode(downloadTaskID)"
      )
    }

    // v17: Rename media column to mediaURL for clarity
    migrator.registerMigration("v17") { db in
      // SQLite doesn't support RENAME COLUMN directly, so we need to:
      // 1. Create a new table with the correct column name
      // 2. Copy data from old table to new table
      // 3. Drop the old table
      // 4. Rename the new table to the original name

      // Create new episode table with mediaURL column
      try db.create(table: "new_episode") { t in
        t.autoIncrementedPrimaryKey("id")
        t.uniqueKey(["podcastId", "guid"], onConflict: .fail)
        t.uniqueKey(["podcastId", "mediaURL"], onConflict: .fail)
        t.uniqueKey(["guid", "mediaURL"], onConflict: .fail)
        t.belongsTo("podcast", onDelete: .cascade).notNull()

        // Feed Info (Required)
        t.column("guid", .text).notNull().indexed()
        t.column("mediaURL", .text).notNull().indexed()
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
        t.column("downloadTaskID", .integer).unique(onConflict: .fail)
        t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
      }

      // Copy data from old table to new table
      try db.execute(
        sql: """
          INSERT INTO new_episode (
            id, podcastId, guid, mediaURL, title, pubDate, duration, description, 
            link, image, completionDate, currentTime, queueOrder, lastQueued, 
            cachedFilename, downloadTaskID, creationDate
          )
          SELECT 
            id, podcastId, guid, media, title, pubDate, duration, description, 
            link, image, completionDate, currentTime, queueOrder, lastQueued, 
            cachedFilename, downloadTaskID, creationDate
          FROM episode
          """
      )

      // Drop the old table
      try db.execute(sql: "DROP TABLE episode")

      // Rename new table to episode
      try db.execute(sql: "ALTER TABLE new_episode RENAME TO episode")
    }

    return migrator
  }
}
