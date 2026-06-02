// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV37(_ db: Database) throws {
    // SQLite forbids CURRENT_TIMESTAMP (or any non-constant) as a DEFAULT on
    // ALTER TABLE ADD COLUMN when the table already has rows. To land a
    // NOT NULL contentUpdatedAt with CURRENT_TIMESTAMP default we rebuild
    // episode and podcast following the SQLite 12-step procedure:
    // https://www.sqlite.org/lang_altertable.html#otheralter
    //
    // Existing rows carry creationDate forward as contentUpdatedAt so any
    // embeddings already computed stay fresh until the content-change
    // trigger fires. Foreign keys are deferred so the DROP/RENAME leaves
    // child tables (episodeEmbedding, podcastEmbedding, episodeTag,
    // podcastTag) with dangling references during the migration; integrity
    // is validated at commit time, and we PRAGMA foreign_key_check before
    // returning so a mistake fails the migration instead of shipping.
    try db.execute(sql: "PRAGMA defer_foreign_keys = 1")

    // MARK: episode rebuild

    try db.create(table: "episode_new") { t in
      t.autoIncrementedPrimaryKey("id")
      t.uniqueKey(["podcastId", "guid"], onConflict: .fail)
      t.uniqueKey(["podcastId", "mediaURL"], onConflict: .fail)
      t.uniqueKey(["guid", "mediaURL"], onConflict: .fail)
      t.column("podcastId", .integer)
        .notNull()
        .references("podcast", onDelete: .cascade)
      t.column("guid", .text).notNull()
      t.column("mediaURL", .text).notNull()
      t.column("title", .text).notNull()
      t.column("pubDate", .datetime).notNull()
      t.column("duration", .integer)
      t.column("description", .text)
      t.column("link", .text)
      t.column("image", .text)
      t.column("finishDate", .datetime)
      t.column("currentTime", .integer).notNull().defaults(to: 0)
      t.column("queueOrder", .integer).check { $0 >= 0 }
      t.column("queueDate", .datetime)
      t.column("cachedFilename", .text)
      t.column("downloadTaskID", .integer).unique(onConflict: .fail)
      t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
      t.column("saveInCache", .boolean).notNull().defaults(to: false)
      t.column("maxPlaybackTime", .integer).notNull().defaults(to: 0)
      t.column("rating", .text)
        .check { $0 == nil || $0 == "loved" || $0 == "liked" || $0 == "disliked" }
      t.column("ratingDate", .datetime)
      t.column("contentUpdatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    }

    try db.execute(
      sql: """
        INSERT INTO episode_new (
          id, podcastId, guid, mediaURL, title, pubDate, duration, description,
          link, image, finishDate, currentTime, queueOrder, queueDate,
          cachedFilename, downloadTaskID, creationDate, saveInCache,
          maxPlaybackTime, rating, ratingDate, contentUpdatedAt
        )
        SELECT
          id, podcastId, guid, mediaURL, title, pubDate, duration, description,
          link, image, finishDate, currentTime, queueOrder, queueDate,
          cachedFilename, downloadTaskID, creationDate, saveInCache,
          maxPlaybackTime, rating, ratingDate, creationDate
        FROM episode
        """
    )

    try db.execute(sql: "DROP TABLE episode")
    try db.execute(sql: "ALTER TABLE episode_new RENAME TO episode")

    // Recreate the non-UNIQUE indexes. The UNIQUE-constraint indexes
    // (sqlite_autoindex_episode_N) were already carried over by SQLite
    // because they're attached to the table definition itself.
    try db.create(index: "episode_on_podcastId", on: "episode", columns: ["podcastId"])
    try db.create(index: "episode_on_guid", on: "episode", columns: ["guid"])
    try db.create(index: "episode_on_mediaURL", on: "episode", columns: ["mediaURL"])
    try db.create(
      index: "episode_on_queueOrder",
      on: "episode",
      columns: ["queueOrder"],
      condition: Column("queueOrder") != nil
    )

    // MARK: podcast rebuild

    try db.create(table: "podcast_new") { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("feedURL", .text).unique(onConflict: .fail).notNull()
      t.column("title", .text).notNull()
      t.column("image", .text).notNull()
      t.column("description", .text).notNull()
      t.column("link", .text)
      t.column("lastUpdate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
      t.column("subscriptionDate", .datetime)
      t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
      t.column("defaultPlaybackRate", .double).check { $0 >= 0.8 && $0 <= 2.0 }
      t.column("queueAllEpisodes", .text).notNull().defaults(to: "never")
      t.column("cacheAllEpisodes", .text).notNull().defaults(to: "never")
      t.column("notifyNewEpisodes", .boolean).notNull().defaults(to: false)
      t.column("iTunesID", .integer)
      t.column("contentUpdatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    }

    try db.execute(
      sql: """
        INSERT INTO podcast_new (
          id, feedURL, title, image, description, link, lastUpdate,
          subscriptionDate, creationDate, defaultPlaybackRate, queueAllEpisodes,
          cacheAllEpisodes, notifyNewEpisodes, iTunesID, contentUpdatedAt
        )
        SELECT
          id, feedURL, title, image, description, link, lastUpdate,
          subscriptionDate, creationDate, defaultPlaybackRate, queueAllEpisodes,
          cacheAllEpisodes, notifyNewEpisodes, iTunesID, creationDate
        FROM podcast
        """
    )

    try db.execute(sql: "DROP TABLE podcast")
    try db.execute(sql: "ALTER TABLE podcast_new RENAME TO podcast")

    // feedURL's UNIQUE constraint already creates an autoindex. v1's .indexed()
    // on the same column was silently deduplicated by GRDB, so the
    // pre-v37 schema has only the UNIQUE autoindex + iTunesID's v31 index.
    try db.create(
      index: "podcast_on_iTunesID",
      on: "podcast",
      columns: ["iTunesID"],
      options: .unique
    )

    // MARK: content-change triggers

    try db.execute(
      sql: """
        CREATE TRIGGER episode_content_updated AFTER UPDATE ON episode
        WHEN OLD.title IS NOT NEW.title OR OLD.description IS NOT NEW.description
        BEGIN
          UPDATE episode SET contentUpdatedAt = CURRENT_TIMESTAMP WHERE id = NEW.id;
        END
        """
    )

    try db.execute(
      sql: """
        CREATE TRIGGER podcast_content_updated AFTER UPDATE ON podcast
        WHEN OLD.description IS NOT NEW.description
        BEGIN
          UPDATE podcast SET contentUpdatedAt = CURRENT_TIMESTAMP WHERE id = NEW.id;
        END
        """
    )

    // Fail the migration (rolling back the transaction) if the rebuild left
    // any dangling foreign keys.
    let fkViolations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
    if !fkViolations.isEmpty {
      throw DatabaseError(
        resultCode: .SQLITE_CONSTRAINT_FOREIGNKEY,
        message: "v37 foreign_key_check failed: \(fkViolations)"
      )
    }
  }
}
