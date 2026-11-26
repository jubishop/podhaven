// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV90(_ db: Database) throws {
    try db.execute(sql: "DELETE FROM episodeEmbeddingFailure")
  }
}
