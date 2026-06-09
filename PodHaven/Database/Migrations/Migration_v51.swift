// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV51(_ db: Database) throws {
    // `updateInferredFreshnessCadence` filters episodes by podcastId and orders
    // by pubDate; the standalone podcastId index forced a filesort. The composite
    // serves both `WHERE podcastId = ?` and the ordered LIMIT, so the standalone
    // is redundant.
    try db.drop(index: "episode_on_podcastId")
    try db.create(
      index: "episode_on_podcastId_pubDate",
      on: "episode",
      columns: ["podcastId", "pubDate"]
    )

    // The embedding work signal reads MAX(contentUpdatedAt) on each table; with
    // these indexes that read is a single b-tree probe instead of a full scan.
    try db.create(
      index: "episode_on_contentUpdatedAt",
      on: "episode",
      columns: ["contentUpdatedAt"]
    )
    try db.create(
      index: "podcast_on_contentUpdatedAt",
      on: "podcast",
      columns: ["contentUpdatedAt"]
    )

    // Rated episodes are a tiny fraction of the library; a partial index keeps
    // the rated-signal fetch (`Episode.hasRatingSignal`) off a full table scan.
    try db.create(
      index: "episode_on_rating",
      on: "episode",
      columns: ["rating"],
      condition: Column("rating") != nil
    )
  }
}
