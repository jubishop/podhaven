// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  // These FTS5 virtual tables are external-content mirrors: synchronize(withTable:)
  // keeps them current via triggers installed on the source `episode`/`podcast`
  // tables. A future migration that rebuilds either source table (drop + recreate)
  // drops those triggers, so it must also drop and recreate the matching *_fts
  // table to reinstall them and rebuild the index.
  static func migrateV47(_ db: Database) throws {
    try db.create(virtualTable: "episode_fts", using: FTS5()) { t in
      t.synchronize(withTable: "episode")
      t.column("title")
      t.column("description")
    }
    try db.create(virtualTable: "podcast_fts", using: FTS5()) { t in
      t.synchronize(withTable: "podcast")
      t.column("title")
      t.column("description")
    }
  }
}
