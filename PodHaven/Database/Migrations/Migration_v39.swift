// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV39(_ db: Database) throws {
    // Hoisted to a `let` so the check closure stays a single `.contains`
    // call — chaining four `||` equalities inline tripped SwiftCompiler's
    // type-checker timeout on cold CI builds.
    let allowedCadences = ["daily", "weekly", "monthly", "evergreen"]
    try db.alter(table: "podcast") { t in
      t.add(column: "freshnessCadence", .text)
        .check { $0 == nil || allowedCadences.contains($0) }
    }
    try db.execute(sql: "ALTER TABLE podcast DROP COLUMN freshnessHalfLifeDays")
  }
}
