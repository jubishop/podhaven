// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV25(_ db: Database) throws {
    // Add partial index on queueOrder for faster queue queries.
    // This optimizes both the filter (queueOrder IS NOT NULL) and sort (ORDER BY queueOrder).
    try db.create(
      index: "episode_on_queueOrder",
      on: "episode",
      columns: ["queueOrder"],
      condition: Column("queueOrder") != nil
    )
  }
}
