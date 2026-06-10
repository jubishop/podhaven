// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV53(_ db: Database) throws {
    // The embedding-needs scan can be answered from a covering index instead of
    // loading vector rows for every candidate.
    try db.create(
      index: "episodeEmbedding_on_episodeId_embeddingRevision_verificationDate",
      on: "episodeEmbedding",
      columns: ["episodeId", "embeddingRevision", "verificationDate"]
    )
  }
}
