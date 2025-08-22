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
        t.column("completed", .boolean).notNull().defaults(to: false)
        t.column("currentTime", .integer).notNull().defaults(to: 0)
        t.column("queueOrder", .integer).check { $0 >= 0 }
      }
    }

    migrator.registerMigration("v2") { db in
      // Migrate from completed boolean to optional completionDate
      try db.alter(table: "episode") { t in
        t.add(column: "completionDate", .datetime)
      }

      try db.execute(sql: "UPDATE episode SET completionDate = pubDate WHERE completed = 1")

      try db.alter(table: "episode") { t in
        t.drop(column: "completed")
      }
    }

    migrator.registerMigration("v3") { db in
      // Fix issue where episodes were not marked complete for a while
      try db.execute(
        sql: """
          UPDATE episode 
          SET completionDate = CURRENT_TIMESTAMP, currentTime = 0 
          WHERE completionDate IS NULL 
            AND duration > 0 
            AND currentTime >= (duration * 0.95)
          """
      )
    }

    migrator.registerMigration("v4") { db in
      // Add trigger to prevent GUID updates on existing episodes
      try db.execute(
        sql: """
          CREATE TRIGGER prevent_episode_guid_update
          BEFORE UPDATE OF guid ON episode
          FOR EACH ROW
          WHEN OLD.guid != NEW.guid
          BEGIN
            SELECT RAISE(ABORT, 'Episode GUID cannot be modified once set');
          END
          """
      )
    }

    migrator.registerMigration("v5") { db in
      // Fix duplicate queueOrder values by reassigning unique values
      // When episodes have the same queueOrder, give older episodes higher queueOrder
      try db.execute(
        sql: """
          WITH ranked_episodes AS (
            SELECT 
              id,
              queueOrder,
              ROW_NUMBER() OVER (
                PARTITION BY queueOrder 
                ORDER BY pubDate ASC, id ASC
              ) - 1 AS rank_within_group,
              ROW_NUMBER() OVER (ORDER BY queueOrder ASC, pubDate ASC, id ASC) - 1 AS new_queue_order
            FROM episode 
            WHERE queueOrder IS NOT NULL
          )
          UPDATE episode 
          SET queueOrder = (
            SELECT new_queue_order 
            FROM ranked_episodes 
            WHERE ranked_episodes.id = episode.id
          )
          WHERE id IN (SELECT id FROM ranked_episodes)
          """
      )
    }

    migrator.registerMigration("v6") { db in
      // Change episode.media constraint from globally unique to unique per podcast
      // SQLite doesn't support dropping constraints directly, so we need to recreate the table

      // Create new table with the correct constraints
      try db.create(table: "episode_new") { t in
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
      }

      // Copy all data from old table to new table
      try db.execute(
        sql: """
          INSERT INTO episode_new (
            id, podcastId, guid, media, title, pubDate, duration, description, 
            link, image, completionDate, currentTime, queueOrder
          )
          SELECT 
            id, podcastId, guid, media, title, pubDate, duration, description, 
            link, image, completionDate, currentTime, queueOrder
          FROM episode
          """
      )

      // Drop old table and rename new one
      try db.drop(table: "episode")
      try db.rename(table: "episode_new", to: "episode")

      // Recreate the GUID update trigger
      try db.execute(
        sql: """
          CREATE TRIGGER prevent_episode_guid_update
          BEFORE UPDATE OF guid ON episode
          FOR EACH ROW
          WHEN OLD.guid != NEW.guid
          BEGIN
            SELECT RAISE(ABORT, 'Episode GUID cannot be modified once set');
          END
          """
      )
    }

    migrator.registerMigration("v7") { db in
      // Remove the GUID update prevention trigger to make GUIDs updateable again
      try db.execute(sql: "DROP TRIGGER IF EXISTS prevent_episode_guid_update")
    }

    migrator.registerMigration("v8") { db in
      // Add lastQueued column to episode table to track when episodes were last added to queue
      try db.alter(table: "episode") { t in
        t.add(column: "lastQueued", .datetime)
      }

      // Populate lastQueued for currently queued episodes
      try db.execute(
        sql: """
          UPDATE episode 
          SET lastQueued = CURRENT_TIMESTAMP 
          WHERE queueOrder IS NOT NULL
          """
      )
    }

    migrator.registerMigration("v9") { db in
      // Migrate from subscribed boolean to subscriptionDate for podcasts
      try db.alter(table: "podcast") { t in
        t.add(column: "subscriptionDate", .datetime)
      }

      // Set subscriptionDate to current timestamp for subscribed podcasts
      try db.execute(
        sql: """
          UPDATE podcast 
          SET subscriptionDate = CURRENT_TIMESTAMP 
          WHERE subscribed = 1
          """
      )

      // Drop the old subscribed column
      try db.alter(table: "podcast") { t in
        t.drop(column: "subscribed")
      }
    }

    migrator.registerMigration("v10") { db in
      // Add cachedMediaURL column to episode table for local caching
      try db.alter(table: "episode") { t in
        t.add(column: "cachedMediaURL", .text)
      }
    }

    migrator.registerMigration("v11") { db in
      // Clear all cachedMediaURL entries due to cache directory change from Caches to Application Support
      // The Caches directory gets deleted during app updates, making all cached paths invalid
      try db.execute(
        sql: "UPDATE episode SET cachedMediaURL = NULL WHERE cachedMediaURL IS NOT NULL"
      )
    }

    migrator.registerMigration("v12") { db in
      // Replace cachedMediaURL (URL) with cachedFilename (String) for simpler cache management
      // Extract filenames from existing URLs and preserve cache data

      // First, add the new cachedFilename column
      try db.alter(table: "episode") { t in
        t.add(column: "cachedFilename", .text)
      }

      // Fetch all episodes with cached URLs and extract filenames using Swift
      let episodesWithCache = try Row.fetchAll(
        db,
        sql: "SELECT id, cachedMediaURL FROM episode WHERE cachedMediaURL IS NOT NULL"
      )

      // Extract filenames and update each episode
      for episode in episodesWithCache {
        guard let episodeId = episode["id"] as? Int64,
          let cachedURLString = episode["cachedMediaURL"] as? String
        else { continue }

        // Extract filename from URL string (handles both file:// URLs and plain paths)
        let filename: String
        if let url = URL(string: cachedURLString) {
          filename = url.lastPathComponent
        } else {
          filename = URL(fileURLWithPath: cachedURLString).lastPathComponent
        }

        // Skip if we couldn't extract a meaningful filename
        guard !filename.isEmpty
        else { continue }

        // Update the episode with extracted filename
        try db.execute(
          sql: "UPDATE episode SET cachedFilename = ? WHERE id = ?",
          arguments: [filename, episodeId]
        )
      }

      // Now drop the old cachedMediaURL column
      try db.alter(table: "episode") { t in
        t.drop(column: "cachedMediaURL")
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
