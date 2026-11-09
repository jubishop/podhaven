// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV86(_ db: Database) throws {
    // Each partial index spans only the rows its condition admits, so a query
    // filtering on that condition reads the small subset instead of scanning
    // the episode table. The pubDate keys also serve the newest-first list
    // order. The coverage index keys on id, not the coverage blob, so playback
    // checkpoint writes never rewrite a large, growing index key.
    try db.create(
      index: "episode_downloading_on_id",
      on: "episode",
      columns: ["id"],
      condition: Column("downloading") == true
    )
    try db.create(
      index: "episode_started_on_pubDate",
      on: "episode",
      columns: ["pubDate"],
      condition: Column("playbackStarted") == true
    )
    try db.create(
      index: "episode_transcribed_on_pubDate",
      on: "episode",
      columns: ["pubDate"],
      condition: Column("transcript") != nil
    )
    try db.create(
      index: "episode_covered_on_id",
      on: "episode",
      columns: ["id"],
      condition: Column("playbackCoverage") != nil
    )

    // Refresh planner statistics so the new indexes are chosen.
    try db.execute(sql: "ANALYZE")
  }
}
