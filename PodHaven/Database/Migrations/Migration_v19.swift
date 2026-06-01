// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV19(_ db: Database) throws {
    try db.alter(table: "episode") { t in
      t.rename(column: "completionDate", to: "finishDate")
    }
  }
}
