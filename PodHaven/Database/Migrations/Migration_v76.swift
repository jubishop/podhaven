// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV76(_ db: Database) throws {
    try db.alter(table: "podcast") { t in
      t.add(column: "alwaysTranscribeNewEpisodes", .boolean)
        .notNull()
        .defaults(to: false)
    }
  }
}
