// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV68(_ db: Database) throws {
    // Preserve ordering against GRDB's millisecond embedding verification dates.
    try db.execute(sql: "DROP TRIGGER IF EXISTS episode_content_updated")
    try db.execute(
      sql: """
        CREATE TRIGGER episode_content_updated AFTER UPDATE ON episode
        WHEN OLD.title IS NOT NEW.title OR OLD.description IS NOT NEW.description
        BEGIN
          UPDATE episode
          SET contentUpdatedAt = STRFTIME('%Y-%m-%d %H:%M:%f', 'now')
          WHERE id = NEW.id;
        END
        """
    )

    try db.execute(sql: "DROP TRIGGER IF EXISTS podcast_content_updated")
    try db.execute(
      sql: """
        CREATE TRIGGER podcast_content_updated AFTER UPDATE ON podcast
        WHEN OLD.title IS NOT NEW.title OR OLD.description IS NOT NEW.description
        BEGIN
          UPDATE podcast
          SET contentUpdatedAt = STRFTIME('%Y-%m-%d %H:%M:%f', 'now')
          WHERE id = NEW.id;
        END
        """
    )

    // Content triggers perform nested timestamp-only updates. Restrict FTS
    // synchronization to indexed columns so those updates cannot perturb it.
    try db.execute(sql: "DROP TRIGGER IF EXISTS __episode_fts_au")
    try db.execute(
      sql: """
        CREATE TRIGGER __episode_fts_au
        AFTER UPDATE OF title, description ON episode
        WHEN OLD.title IS NOT NEW.title OR OLD.description IS NOT NEW.description
        BEGIN
          INSERT INTO episode_fts(episode_fts, rowid, title, description)
          VALUES ('delete', OLD.id, OLD.title, OLD.description);
          INSERT INTO episode_fts(rowid, title, description)
          VALUES (NEW.id, NEW.title, NEW.description);
        END
        """
    )

    try db.execute(sql: "DROP TRIGGER IF EXISTS __podcast_fts_au")
    try db.execute(
      sql: """
        CREATE TRIGGER __podcast_fts_au
        AFTER UPDATE OF title, description ON podcast
        WHEN OLD.title IS NOT NEW.title OR OLD.description IS NOT NEW.description
        BEGIN
          INSERT INTO podcast_fts(podcast_fts, rowid, title, description)
          VALUES ('delete', OLD.id, OLD.title, OLD.description);
          INSERT INTO podcast_fts(rowid, title, description)
          VALUES (NEW.id, NEW.title, NEW.description);
        END
        """
    )
  }
}
