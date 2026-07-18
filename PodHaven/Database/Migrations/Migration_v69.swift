// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV69(_ db: Database) throws {
    try db.create(table: "episodeEmbeddingFailure") { t in
      t.primaryKey("episodeId", .integer).references("episode", onDelete: .cascade)
      t.column("episodeContentUpdatedAt", .datetime).notNull()
      t.column("podcastContentUpdatedAt", .datetime).notNull()
      t.column("embeddingRevision", .integer).notNull()
      t.column("recipeVersion", .integer).notNull()
      t.column("attemptCount", .integer).notNull().check { $0 >= 1 }
    }
  }
}
