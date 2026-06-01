// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV35(_ db: Database) throws {
    try db.alter(table: "episode") { t in
      t.add(column: "rating", .text)
        .check { $0 == nil || $0 == "loved" || $0 == "liked" || $0 == "disliked" }
      t.add(column: "ratingDate", .datetime)
    }
  }
}
