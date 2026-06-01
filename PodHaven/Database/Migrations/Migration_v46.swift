// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV46(_ db: Database) throws {
    // Overlapping feeds — a Substack aggregate feed and its per-section
    // feeds, or any republished show — legitimately carry the same episode
    // under different podcasts with identical guid and mediaURL. The global
    // (guid, mediaURL) unique key rejected the second podcast's insert and
    // rolled the entire refresh back, discarding every other episode in that
    // feed. Scope episode uniqueness to the per-podcast keys only.
    // 12-step procedure: https://www.sqlite.org/lang_altertable.html#otheralter
    try db.execute(sql: "PRAGMA defer_foreign_keys = 1")

    let allowedRatings = ["loved", "liked", "disliked", "notInterested"]
    try db.create(table: "episode_new") { t in
      t.autoIncrementedPrimaryKey("id")
      t.uniqueKey(["podcastId", "guid"], onConflict: .fail)
      t.uniqueKey(["podcastId", "mediaURL"], onConflict: .fail)
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
      t.column("downloading", .boolean).notNull().defaults(to: false)
      t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
      t.column("saveInCache", .boolean).notNull().defaults(to: false)
      t.column("maxPlaybackTime", .integer).notNull().defaults(to: 0)
      t.column("rating", .text)
        .check { $0 == nil || allowedRatings.contains($0) }
      t.column("ratingDate", .datetime)
      t.column("contentUpdatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
      t.column("playbackCoverage", .blob)
      t.column("lastPlayedDate", .datetime)
    }

    try db.execute(
      sql: """
        INSERT INTO episode_new (
          id, podcastId, guid, mediaURL, title, pubDate, duration, description,
          link, image, finishDate, currentTime, queueOrder, queueDate,
          cachedFilename, downloading, creationDate, saveInCache,
          maxPlaybackTime, rating, ratingDate, contentUpdatedAt,
          playbackCoverage, lastPlayedDate
        )
        SELECT
          id, podcastId, guid, mediaURL, title, pubDate, duration, description,
          link, image, finishDate, currentTime, queueOrder, queueDate,
          cachedFilename, downloading, creationDate, saveInCache,
          maxPlaybackTime, rating, ratingDate, contentUpdatedAt,
          playbackCoverage, lastPlayedDate
        FROM episode
        """
    )

    try db.execute(sql: "DROP TRIGGER IF EXISTS episode_content_updated")
    try db.execute(sql: "DROP TABLE episode")
    try db.execute(sql: "ALTER TABLE episode_new RENAME TO episode")

    try db.create(index: "episode_on_podcastId", on: "episode", columns: ["podcastId"])
    try db.create(index: "episode_on_guid", on: "episode", columns: ["guid"])
    try db.create(index: "episode_on_mediaURL", on: "episode", columns: ["mediaURL"])
    try db.create(
      index: "episode_on_queueOrder",
      on: "episode",
      columns: ["queueOrder"],
      condition: Column("queueOrder") != nil
    )
    try db.create(index: "episode_on_pubDate", on: "episode", columns: ["pubDate"])

    try db.execute(
      sql: """
        CREATE TRIGGER episode_content_updated AFTER UPDATE ON episode
        WHEN OLD.title IS NOT NEW.title OR OLD.description IS NOT NEW.description
        BEGIN
          UPDATE episode SET contentUpdatedAt = CURRENT_TIMESTAMP WHERE id = NEW.id;
        END
        """
    )

    let fkViolations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
    if !fkViolations.isEmpty {
      throw DatabaseError(
        resultCode: .SQLITE_CONSTRAINT_FOREIGNKEY,
        message: "v46 foreign_key_check failed: \(fkViolations)"
      )
    }
  }
}
