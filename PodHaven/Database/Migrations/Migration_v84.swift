// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV84(_ db: Database) throws {
    try db.create(table: "siriCatalogRevision") { table in
      table.primaryKey("id", .integer).check { $0 == 1 }
      table.column("revision", .integer).notNull()
    }
    try db.execute(
      sql: """
        INSERT INTO siriCatalogRevision (id, revision) VALUES (1, random());
        CREATE TRIGGER podcast_siri_catalog_insert AFTER INSERT ON podcast
        BEGIN
          UPDATE siriCatalogRevision SET revision = random();
        END;
        CREATE TRIGGER podcast_siri_catalog_delete AFTER DELETE ON podcast
        BEGIN
          UPDATE siriCatalogRevision SET revision = random();
        END;
        CREATE TRIGGER podcast_siri_catalog_update AFTER UPDATE OF title, feedURL ON podcast
        BEGIN
          UPDATE siriCatalogRevision SET revision = random();
        END;
        CREATE TRIGGER episode_siri_catalog_insert AFTER INSERT ON episode
        BEGIN
          UPDATE siriCatalogRevision SET revision = random();
        END;
        CREATE TRIGGER episode_siri_catalog_delete AFTER DELETE ON episode
        BEGIN
          UPDATE siriCatalogRevision SET revision = random();
        END;
        CREATE TRIGGER episode_siri_catalog_update
        AFTER UPDATE OF title, guid, podcastId, pubDate, finishDate ON episode
        BEGIN
          UPDATE siriCatalogRevision SET revision = random();
        END;
        """
    )
  }
}
