// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV36(_ db: Database) throws {
    try db.create(table: "episodeEmbedding") { t in
      t.autoIncrementedPrimaryKey("id")
      t.belongsTo("episode", onDelete: .cascade).notNull().unique()
      t.column("vector", .blob).notNull()
      t.column("sourceHash", .text).notNull()
      t.column("embeddingRevision", .integer).notNull()
      t.column("dimension", .integer).notNull()
      t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    }

    try db.create(table: "podcastEmbedding") { t in
      t.autoIncrementedPrimaryKey("id")
      t.belongsTo("podcast", onDelete: .cascade).notNull().unique()
      t.column("vector", .blob).notNull()
      t.column("sourceHash", .text).notNull()
      t.column("embeddingRevision", .integer).notNull()
      t.column("dimension", .integer).notNull()
      t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    }
  }
}
