// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV75(_ db: Database) throws {
    try db.create(
      index: "episode_on_cachedFilename",
      on: "episode",
      columns: ["cachedFilename"],
      condition: Column("cachedFilename") != nil
    )
  }
}
