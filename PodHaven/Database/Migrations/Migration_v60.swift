// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV60(_ db: Database) throws {
    // The equals text operator is removed; fold any saved filter using it into
    // contains. JSONEncoder emits compact JSON so the operator token is exact,
    // and a user value containing the literal would be quote-escaped and cannot
    // match this pattern.
    try db.execute(
      sql: """
        UPDATE smartList
        SET filter = REPLACE(filter, '"op":"equals"', '"op":"contains"')
        WHERE filter LIKE '%"op":"equals"%'
        """
    )
  }
}
