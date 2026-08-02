// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV80(_ db: Database) throws {
    try db.create(table: "publisherTranscriptImportJob") { table in
      table.column("episodeId", .integer).primaryKey()
        .references("episode", onDelete: .cascade)
      table.column("attemptCount", .integer).notNull().defaults(to: 0)
        .check { $0 >= 0 }
      table.column("nextAttemptAt", .datetime).notNull()
    }
  }
}
