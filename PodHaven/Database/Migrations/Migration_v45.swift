// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV45(_ db: Database) throws {
    // The embedding background task uses `Episode.contentUpdatedAt >
    // embedding.creationDate` to decide whether an episode still needs an
    // embedding refresh. But the Swift loop short-circuits via a hash check
    // and skips the recompute (and the row touch) whenever the cleaned
    // title/description hash is unchanged — so creationDate never advances,
    // contentUpdatedAt stays ahead forever, and the same episodes re-enter
    // the queue every hour without ever draining. Split the "when did we
    // last verify this embedding is still current" stamp out of the
    // immutable creationDate into a separate, mutable verificationDate.
    //
    // SQLite forbids non-constant DEFAULTs (e.g. CURRENT_TIMESTAMP) on
    // ALTER TABLE ADD COLUMN when the table already has rows, so add the
    // column with a constant default and immediately backfill from
    // creationDate.
    try db.execute(
      sql: """
        ALTER TABLE episodeEmbedding
        ADD COLUMN verificationDate DATETIME NOT NULL DEFAULT 0
        """
    )
    try db.execute(sql: "UPDATE episodeEmbedding SET verificationDate = creationDate")
  }
}
