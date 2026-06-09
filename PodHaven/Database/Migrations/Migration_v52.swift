// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV52(_ db: Database) throws {
    // The embedding-needs scan probes episodeEmbedding by episodeId and reads
    // only embeddingRevision and verificationDate. The covering composite
    // answers each probe from the index alone, instead of fetching a row that
    // carries the full vector blob.
    try db.create(
      index: "episodeEmbedding_on_episodeId_embeddingRevision_verificationDate",
      on: "episodeEmbedding",
      columns: ["episodeId", "embeddingRevision", "verificationDate"]
    )
  }
}
