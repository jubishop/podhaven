// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV49(_ db: Database) throws {
    // v39's freshnessCadence CHECK only allowed daily/weekly/monthly/evergreen.
    // The finer-grained cadences (hourly, twiceDaily, twiceWeekly) need the
    // constraint widened, and SQLite can't alter a CHECK in place, so rebuild
    // the table following the 12-step procedure:
    // https://www.sqlite.org/lang_altertable.html#otheralter
    try db.execute(sql: "PRAGMA defer_foreign_keys = 1")

    // Hoisted to a `let` so the check closure stays a single `.contains`
    // call — chaining the equalities inline trips SwiftCompiler's
    // type-checker timeout on cold CI builds.
    let allowedCadences = [
      "hourly", "twiceDaily", "daily", "twiceWeekly", "weekly", "monthly", "evergreen",
    ]
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
      t.column("freshnessCadence", .text)
        .check { $0 == nil || allowedCadences.contains($0) }
      t.column("autoQueueLimit", .integer).check { $0 == nil || ($0 >= 1 && $0 <= 5) }
    }

    try db.execute(
      sql: """
        INSERT INTO podcast_new (
          id, feedURL, title, image, description, link, lastUpdate,
          subscriptionDate, creationDate, defaultPlaybackRate, queueAllEpisodes,
          cacheAllEpisodes, notifyNewEpisodes, iTunesID, contentUpdatedAt,
          freshnessCadence, autoQueueLimit
        )
        SELECT
          id, feedURL, title, image, description, link, lastUpdate,
          subscriptionDate, creationDate, defaultPlaybackRate, queueAllEpisodes,
          cacheAllEpisodes, notifyNewEpisodes, iTunesID, contentUpdatedAt,
          freshnessCadence, autoQueueLimit
        FROM podcast
        """
    )

    try db.execute(sql: "DROP TRIGGER IF EXISTS podcast_content_updated")
    try db.execute(sql: "DROP TABLE podcast")
    try db.execute(sql: "ALTER TABLE podcast_new RENAME TO podcast")

    try db.create(
      index: "podcast_on_iTunesID",
      on: "podcast",
      columns: ["iTunesID"],
      options: .unique
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

    // Dropping `podcast` above also dropped the FTS5 sync triggers the v48
    // migration installed on it, leaving `podcast_fts` orphaned. Recreate the
    // mirror so synchronize reinstalls the triggers and rebuilds the index
    // against the new table.
    try db.drop(table: "podcast_fts")
    try db.create(virtualTable: "podcast_fts", using: FTS5()) { t in
      t.synchronize(withTable: "podcast")
      t.column("title")
      t.column("description")
    }

    let fkViolations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
    if !fkViolations.isEmpty {
      throw DatabaseError(
        resultCode: .SQLITE_CONSTRAINT_FOREIGNKEY,
        message: "v49 foreign_key_check failed: \(fkViolations)"
      )
    }
  }
}
