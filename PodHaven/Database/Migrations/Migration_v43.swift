// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV43(_ db: Database) throws {
    try db.create(index: "episode_on_pubDate", on: "episode", columns: ["pubDate"])
  }
}
