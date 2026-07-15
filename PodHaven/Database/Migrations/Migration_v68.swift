// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV68(_ db: Database) throws {
    try db.execute(sql: "DROP TRIGGER IF EXISTS podcast_content_updated")
    try db.execute(
      sql: """
        CREATE TRIGGER podcast_content_updated AFTER UPDATE ON podcast
        WHEN OLD.title IS NOT NEW.title OR OLD.description IS NOT NEW.description
        BEGIN
          UPDATE podcast SET contentUpdatedAt = CURRENT_TIMESTAMP WHERE id = NEW.id;
        END
        """
    )

    // The content trigger performs a nested timestamp-only update. Restrict
    // FTS synchronization to indexed columns so that update cannot write a
    // duplicate entry while the outer title or description update is active.
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
