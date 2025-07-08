// Copyright Justin Bishop, 2025

import Foundation
import GRDB

enum Schema {
  // MARK: - Columns

  static let id = Column("id")

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

    return migrator
  }
}
