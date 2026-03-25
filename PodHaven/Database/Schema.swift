// Copyright Justin Bishop, 2025

import FactoryKit
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
        do {
          let data = try JSONEncoder().encode(nativeValue())
          defaults.set(data, forKey: key)
        } catch {
          log.caughtError(
            "v29 migration: failed to encode '\(key)' (\(type(of: existing)))",
            error,
            remarkable: .info
          )
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

    // Note: the widget extension may refresh before the app runs this migration,
    // briefly showing empty widgets until the user opens the app. This is acceptable
    // — the window is short, the .empty states are designed for it, and adding a
    // fallback reader for the legacy file isn't worth the complexity.
    migrator.registerMigration("v30") { _ in
      guard
        let containerURL = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: AppInfo.appGroupID
        )
      else {
        log.warning("v30: app group container not found, skipping widget snapshot migration")
        return
      }
      migrateWidgetSnapshotFiles(in: containerURL)
    }

    migrator.registerMigration("v31") { db in
      try db.alter(table: "podcast") { t in
        t.add(column: "iTunesID", .integer)
      }
      try db.create(indexOn: "podcast", columns: ["iTunesID"], options: .unique)
    }

    migrator.registerMigration("v32") { db in
      // Cap maxQueueLength at 100 (previously allowed up to 500).
      let defaults = Container.shared.standardDefaults()
      let key = "maxQueueLength"
      if let data = defaults.data(forKey: key),
        let current = try? JSONDecoder().decode(Int.self, from: data),
        current > 100
      {
        let clamped = try JSONEncoder().encode(100)
        defaults.set(clamped, forKey: key)
        log.info("v32: clamped maxQueueLength from \(current) to 100")
      }

      // Trim queued episodes beyond position 100.
      // queueOrder is always a dense 0-based sequence, so this is equivalent
      // to removing everything past the 100th item.
      try db.execute(sql: "UPDATE episode SET queueOrder = NULL WHERE queueOrder >= 100")
    }

    migrator.registerMigration("v33") { _ in
      cleanupStaleKeys(
        in: Container.shared.standardDefaults(),
        activeKeys: [
          "shrinkPlayBarOnScroll",
          "cacheSizeLimitGB",
          "defaultPlaybackRate",
          "skipForwardInterval",
          "skipBackwardInterval",
          "enableUndoSeek",
          "maxQueueLength",
          "showNowPlayingInUpNext",
          "alwaysShowPodcastImageInUpNext",
          "showTimeRemainingInEpisodeLists",
          "appearanceMode",
          "nextTrackBehavior",
          "currentEpisodeID",
          "PodcastsList-displayMode",
          "SearchView-displayMode",
        ],
        activePrefixes: [
          "PodcastsList-sortMethod-",
          "EpisodesList-sortMethod-",
        ]
      )
      cleanupStaleKeys(
        in: Container.shared.sharedDefaults(),
        activeKeys: [
          "skipForwardInterval",
          "skipBackwardInterval",
          "playbackStatus",
        ]
      )
    }

    return migrator
  }

  // MARK: - v33: Stale Defaults Cleanup

  // Removes keys from the store that are not in the active set.
  // Extracted as a static method so it can be tested directly.
  static func cleanupStaleKeys(
    in store: any KeyValueStore,
    activeKeys: Set<String>,
    activePrefixes: [String] = []
  ) {
    for key in store.allKeys {
      let isActive =
        activeKeys.contains(key) || activePrefixes.contains(where: { key.hasPrefix($0) })
      if !isActive {
        store.removeObject(forKey: key)
      }
    }
  }

  // MARK: - v30: Widget Snapshot File Migration

  // Migrate the monolithic widget-snapshot.json into per-widget files.
  // The old format stored all widget data in a single file. The new
  // architecture uses separate files per widget type. Artwork is not
  // migrated — it will be populated on the next writer cycle.
  //
  // Extracted as a static method so it can be tested with a temp directory.
  static func migrateWidgetSnapshotFiles(in containerURL: URL) {
    let oldURL = containerURL.appendingPathComponent("widget-snapshot.json")
    guard FileManager.default.fileExists(atPath: oldURL.path) else {
      log.debug("v30: no legacy widget-snapshot.json, nothing to migrate")
      return
    }

    struct LegacySnapshot: Codable {
      struct NowPlaying: Codable {
        let episodeID: Int64
        let episodeTitle: String
        let podcastTitle: String
        let pubDateTimestamp: Double
        let durationSeconds: Double
      }
      struct QueueItem: Codable {
        let episodeID: Int64
        let episodeTitle: String
        let pubDateTimestamp: Double
        let durationSeconds: Double
      }
      let nowPlaying: NowPlaying?
      let queue: [QueueItem]
      let queueTotalCount: Int
      let updatedAt: Date
    }

    // Self-contained output structs frozen to today's schema (version 1).
    // These must never reference the live snapshot types so the migration
    // stays stable if the types evolve later.
    struct V1NowPlaying: Codable {
      struct NowPlaying: Codable {
        let episodeID: Int64
        let episodeTitle: String
        let podcastTitle: String
        let pubDateTimestamp: Double
        let durationSeconds: Double
        let artworkBase64: String?
      }
      let schemaVersion: Int
      let nowPlaying: NowPlaying?
      let updatedAt: Date
    }
    struct V1Queue: Codable {
      struct QueueItem: Codable {
        let episodeID: Int64
        let episodeTitle: String
        let pubDateTimestamp: Double
        let durationSeconds: Double
        let artworkURL: String?
      }
      let schemaVersion: Int
      let queue: [QueueItem]
      let queueTotalCount: Int
      let artwork: [String: String]
      let updatedAt: Date
    }

    do {
      let data = try Data(contentsOf: oldURL)
      let legacy = try JSONDecoder().decode(LegacySnapshot.self, from: data)
      let now = legacy.updatedAt

      let nowPlayingSnapshot = V1NowPlaying(
        schemaVersion: 1,
        nowPlaying: legacy.nowPlaying.map {
          V1NowPlaying.NowPlaying(
            episodeID: $0.episodeID,
            episodeTitle: $0.episodeTitle,
            podcastTitle: $0.podcastTitle,
            pubDateTimestamp: $0.pubDateTimestamp,
            durationSeconds: $0.durationSeconds,
            artworkBase64: nil
          )
        },
        updatedAt: now
      )
      try JSONEncoder().encode(nowPlayingSnapshot)
        .write(to: containerURL.appendingPathComponent("widget-now-playing.json"))

      let queueSnapshot = V1Queue(
        schemaVersion: 1,
        queue: legacy.queue.map {
          V1Queue.QueueItem(
            episodeID: $0.episodeID,
            episodeTitle: $0.episodeTitle,
            pubDateTimestamp: $0.pubDateTimestamp,
            durationSeconds: $0.durationSeconds,
            artworkURL: nil
          )
        },
        queueTotalCount: legacy.queueTotalCount,
        artwork: [:],
        updatedAt: now
      )
      try JSONEncoder().encode(queueSnapshot)
        .write(to: containerURL.appendingPathComponent("widget-queue.json"))

      try FileManager.default.removeItem(at: oldURL)
      log.info("v30: migrated widget-snapshot.json to per-widget files")
    } catch {
      log.caughtError("v30: failed to migrate widget snapshot", error)
    }
  }
}
