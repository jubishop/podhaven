// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV91(_ db: Database) throws {
    try db.alter(table: "episodeEmbedding") { table in
      table.add(column: "recipeVersion", .integer).notNull().defaults(to: 2)
    }

    // Appending the recipe version lets the scoring observation count
    // current-recipe rows from the covering index instead of vector rows.
    try db.drop(index: "episodeEmbedding_on_episodeId_embeddingRevision_verificationDate")
    try db.create(
      index: "episodeEmbedding_on_episodeId_embeddingRevision_verificationDate_recipeVersion",
      on: "episodeEmbedding",
      columns: ["episodeId", "embeddingRevision", "verificationDate", "recipeVersion"]
    )
  }
}
