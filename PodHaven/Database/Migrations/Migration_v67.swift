// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV67(_ db: Database) throws {
    // User-initiated on-device transcripts, stored as timed-segment JSON.
    // Nullable with no default: existing rows are untranscribed.
    try db.alter(table: "episode") { t in
      t.add(column: "transcript", .text)
    }
  }
}
