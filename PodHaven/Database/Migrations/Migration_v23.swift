// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV23(_ db: Database) throws {
    // Convert cacheAllEpisodes from BOOLEAN to TEXT enum. SQLite doesn't
    // support ALTER COLUMN type, so we add a new column, copy data with
    // conversion, drop the old column, and rename.
    try db.alter(table: "podcast") { t in
      t.add(column: "cacheAllEpisodesNew", .text).notNull().defaults(to: "never")
    }

    try db.execute(
      sql: """
        UPDATE podcast SET cacheAllEpisodesNew = CASE
          WHEN cacheAllEpisodes = 1 THEN 'cache'
          ELSE 'never'
        END
        """
    )

    try db.execute(sql: "ALTER TABLE podcast DROP COLUMN cacheAllEpisodes")

    try db.alter(table: "podcast") { t in
      t.rename(column: "cacheAllEpisodesNew", to: "cacheAllEpisodes")
    }
  }
}
