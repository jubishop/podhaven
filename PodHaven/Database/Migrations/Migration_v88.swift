// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV88(_ db: Database) throws {
    try db.execute(
      sql:
        "UPDATE cachedAudioContent SET failureCount = 0 WHERE analysis IS NULL AND failureCount > 0"
    )
  }
}
