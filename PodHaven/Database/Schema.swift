// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Logging

enum Schema {
  private static let log = Log.as(LogSubsystem.Database.schema)

  // MARK: - Columns

  static let id = Column("id")
  static let creationDate = Column("creationDate")

  // MARK: - Migration

  static func migrate(_ db: some DatabaseWriter) {
    do {
      try makeMigrator().migrate(db)
    } catch {
      Assert.fatal("Schema migration failed: \(ErrorKit.message(for: error))")
    }
  }

  // MARK: - Migrator

  static func makeMigrator() -> DatabaseMigrator {
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
    }

    migrator.registerMigration("v18") { db in
      try db.alter(table: "podcast") { t in
        t.add(column: "defaultPlaybackRate", .double).check { $0 >= 0.8 && $0 <= 2.0 }
      }
    }

    migrator.registerMigration("v19") { db in
      try db.alter(table: "episode") { t in
        t.rename(column: "completionDate", to: "finishDate")
      }
    }

    migrator.registerMigration("v20") { db in
      try db.alter(table: "episode") { t in
        t.rename(column: "lastQueued", to: "queueDate")
      }
    }

    migrator.registerMigration("v21") { db in
      try db.alter(table: "podcast") { t in
        t.add(column: "queueAllEpisodes", .text).notNull().defaults(to: "never")
      }
    }

    migrator.registerMigration("v22") { db in
      try db.alter(table: "episode") { t in
        t.add(column: "saveInCache", .boolean).notNull().defaults(to: false)
      }
    }

    migrator.registerMigration("v23") { db in
      // Convert cacheAllEpisodes from BOOLEAN to TEXT enum
      // SQLite doesn't support ALTER COLUMN type, so we need to:
      // 1. Add a new TEXT column
      // 2. Copy data with conversion (false -> 'never', true -> 'cache')
      // 3. Drop the old column (SQLite 3.35+)
      // 4. Rename the new column

      // Step 1: Add new column
      try db.alter(table: "podcast") { t in
        t.add(column: "cacheAllEpisodesNew", .text).notNull().defaults(to: "never")
      }

      // Step 2: Copy data with conversion (true -> 'cache', false -> 'never')
      try db.execute(
        sql: """
          UPDATE podcast SET cacheAllEpisodesNew = CASE
            WHEN cacheAllEpisodes = 1 THEN 'cache'
            ELSE 'never'
          END
          """
      )

      // Step 3: Drop old column (requires SQLite 3.35.0+, which is available on iOS 15+)
      try db.execute(sql: "ALTER TABLE podcast DROP COLUMN cacheAllEpisodes")

      // Step 4: Rename new column to original name
      try db.alter(table: "podcast") { t in
        t.rename(column: "cacheAllEpisodesNew", to: "cacheAllEpisodes")
      }
    }

    migrator.registerMigration("v24") { db in
      try db.alter(table: "podcast") { t in
        t.add(column: "notifyNewEpisodes", .boolean).notNull().defaults(to: false)
      }
    }

    migrator.registerMigration("v25") { db in
      // Add partial index on queueOrder for faster queue queries.
      // This optimizes both the filter (queueOrder IS NOT NULL) and sort (ORDER BY queueOrder).
      try db.create(
        index: "episode_on_queueOrder",
        on: "episode",
        columns: ["queueOrder"],
        condition: Column("queueOrder") != nil
      )
    }

    migrator.registerMigration("v26") { _ in
      // Migrate currentEpisodeID from PlayManager to SharedState key.
      // This allows the cache purger to protect the current episode even when the app
      // is launched in the background (when onDeck is not populated).
      let oldKey = "PlayManager-currentEpisodeID"
      let newKey = "currentEpisodeID"
      if let oldValue = UserDefaults.standard.object(forKey: oldKey) as? Int {
        UserDefaults.standard.set(oldValue, forKey: newKey)
        UserDefaults.standard.removeObject(forKey: oldKey)
      }
    }

    migrator.registerMigration("v27") { db in
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

    migrator.registerMigration("v28") { db in
      try db.create(table: "episodeTag") { t in
        t.belongsTo("episode", onDelete: .cascade).notNull()
        t.belongsTo("tag", onDelete: .cascade).notNull()
        t.uniqueKey(["episodeId", "tagId"], onConflict: .fail)
      }
    }

    migrator.registerMigration("v29") { _ in
      // Migrate persisted UserDefaults values from native format to JSON Data.
      // Commit 20fd026a changed DefaultsStorable to use Codable (JSON) for all types,
      // but values stored by earlier builds used native UserDefaults storage.
      let defaults = UserDefaults.standard

      func migrate<T: Codable>(_ key: String, _ nativeValue: @autoclosure () -> T) {
        guard let existing = defaults.object(forKey: key), !(existing is Data) else { return }
        if let data = try? JSONEncoder().encode(nativeValue()) {
          defaults.set(data, forKey: key)
        }
      }

      // Int
      migrate("currentEpisodeID", defaults.integer(forKey: "currentEpisodeID"))
      migrate("maxQueueLength", defaults.integer(forKey: "maxQueueLength"))

      // Bool
      migrate("shrinkPlayBarOnScroll", defaults.bool(forKey: "shrinkPlayBarOnScroll"))
      migrate("enableUndoSeek", defaults.bool(forKey: "enableUndoSeek"))
      migrate("showNowPlayingInUpNext", defaults.bool(forKey: "showNowPlayingInUpNext"))
      migrate(
        "alwaysShowPodcastImageInUpNext",
        defaults.bool(forKey: "alwaysShowPodcastImageInUpNext")
      )
      migrate(
        "showTimeRemainingInEpisodeLists",
        defaults.bool(forKey: "showTimeRemainingInEpisodeLists")
      )

      // Double
      migrate("cacheSizeLimitGB", defaults.double(forKey: "cacheSizeLimitGB"))
      migrate("defaultPlaybackRate", defaults.double(forKey: "defaultPlaybackRate"))
      migrate("skipForwardInterval", defaults.double(forKey: "skipForwardInterval"))
      migrate("skipBackwardInterval", defaults.double(forKey: "skipBackwardInterval"))
    }

    return migrator
  }
}
