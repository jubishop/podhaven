// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV85(_ db: Database) throws {
    try db.alter(table: "siriCatalogRevision") { table in
      table.add(column: "finishRevision", .integer).notNull().defaults(to: 0)
    }
    try db.execute(
      sql: """
        UPDATE siriCatalogRevision SET finishRevision = random();
        DROP TRIGGER episode_siri_catalog_update;
        CREATE TRIGGER episode_siri_catalog_update
        AFTER UPDATE OF title, guid, podcastId, pubDate ON episode
        BEGIN
          UPDATE siriCatalogRevision SET revision = random();
        END;
        CREATE TRIGGER episode_siri_catalog_finish AFTER UPDATE OF finishDate ON episode
        BEGIN
          UPDATE siriCatalogRevision SET finishRevision = random();
        END;
        """
    )
  }
}
