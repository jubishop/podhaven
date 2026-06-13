// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV57(_ db: Database) throws {
    // Per-list artwork preference. false (the default) keeps the existing
    // behavior of showing episode-specific artwork when one exists; true always
    // shows the parent podcast's artwork. The default backfills existing rows.
    try db.alter(table: "smartList") { t in
      t.add(column: "alwaysShowPodcastImage", .boolean).notNull().defaults(to: false)
    }
  }
}
