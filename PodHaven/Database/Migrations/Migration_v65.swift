// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV65(_ db: Database) throws {
    try db.execute(
      sql: """
        UPDATE smartList
        SET filter = REPLACE(
          REPLACE(filter, '"kind":"episodeTag"', '"kind":"tag"'),
          '"kind":"podcastTag"',
          '"kind":"tag"'
        )
        WHERE filter LIKE '%"kind":"episodeTag"%'
          OR filter LIKE '%"kind":"podcastTag"%'
        """
    )
  }
}
