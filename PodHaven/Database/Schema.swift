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
      }
    }

    migrator.registerMigration("v13") { db in
      // Add cacheAllEpisodes column to podcast table for controlling episode caching behavior
      try db.alter(table: "podcast") { t in
        t.add(column: "cacheAllEpisodes", .boolean).notNull().defaults(to: false)
      }
    }

    migrator.registerMigration("v14") { db in
      // SQLite doesn't support adding columns with non-constant defaults like CURRENT_TIMESTAMP
      // So we need to recreate the tables with the new column creationDate and default

      // Clean up any leftover temporary tables and indexes from previous migrations
      try db.execute(sql: "DROP INDEX IF EXISTS episode_new_on_podcastId")
      try db.execute(sql: "DROP INDEX IF EXISTS episode_new_on_guid")
      try db.execute(sql: "DROP INDEX IF EXISTS episode_new_on_media")
      try db.execute(sql: "DROP INDEX IF EXISTS podcast_new_on_feedURL")

      // Recreate episode table with creationDate column using unique name
      try db.create(table: "episode_v14") { t in
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

      // Copy all data from old episode table, setting creationDate to current timestamp for existing records
      try db.execute(
        sql: """
          INSERT INTO episode_v14 (
            id, podcastId, guid, media, title, pubDate, duration, description, 
            link, image, completionDate, currentTime, queueOrder, lastQueued, cachedFilename, creationDate
          )
          SELECT 
            id, podcastId, guid, media, title, pubDate, duration, description, 
            link, image, completionDate, currentTime, queueOrder, lastQueued, cachedFilename, CURRENT_TIMESTAMP
          FROM episode
          """
      )

      // Drop old episode table and rename new one
      try db.drop(table: "episode")
      try db.rename(table: "episode_v14", to: "episode")

      // Drop and recreate indexes with correct names
      // GRDB doesn't automatically rename indexes when tables are renamed
      try db.execute(sql: "DROP INDEX IF EXISTS episode_v14_on_podcastId")
      try db.execute(sql: "DROP INDEX IF EXISTS episode_v14_on_guid")
      try db.execute(sql: "DROP INDEX IF EXISTS episode_v14_on_media")

      // Recreate indexes with standard names
      try db.execute(sql: "CREATE INDEX episode_on_podcastId ON episode(podcastId)")
      try db.execute(sql: "CREATE INDEX episode_on_guid ON episode(guid)")
      try db.execute(sql: "CREATE INDEX episode_on_media ON episode(media)")

      // Recreate podcast table with creationDate column
      try db.create(table: "podcast_v14") { t in
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

      // Copy all data from old podcast table, setting creationDate to current timestamp for existing records
      try db.execute(
        sql: """
          INSERT INTO podcast_v14 (
            id, feedURL, title, image, description, link, lastUpdate, subscriptionDate, cacheAllEpisodes, creationDate
          )
          SELECT 
            id, feedURL, title, image, description, link, lastUpdate, subscriptionDate, cacheAllEpisodes, CURRENT_TIMESTAMP
          FROM podcast
          """
      )

      // Drop old podcast table and rename new one
      try db.drop(table: "podcast")
      try db.rename(table: "podcast_v14", to: "podcast")

      // Drop and recreate indexes with correct names
      // GRDB doesn't automatically rename indexes when tables are renamed
      try db.execute(sql: "DROP INDEX IF EXISTS podcast_v14_on_feedURL")

      // Recreate indexes with standard names
      try db.execute(sql: "CREATE INDEX podcast_on_feedURL ON podcast(feedURL)")
    }

    return migrator
  }
}
