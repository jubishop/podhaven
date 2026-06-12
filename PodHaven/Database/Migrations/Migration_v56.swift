// Copyright Justin Bishop, 2026

import Foundation
import GRDB

extension Schema {
  static func migrateV56(_ db: Database) throws {
    // Smart List filters now allow any number of nested groups: the JSON's
    // single optional `nested` object becomes a `groups` array. SQLite can't
    // alter a CHECK constraint, so rebuild the table with the new guard,
    // converting each row's filter in the copy.
    let allowedSortMethods = [
      "newestFirst", "oldestFirst", "recentlyAdded", "longest", "shortest",
      "recentlyFinished", "recentlyQueued", "recommendationScore",
    ]
    try db.create(table: "smartList_new") { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("title", .text).notNull()
      // Guard the top-level shape the decoder requires (object with a text
      // combinator, an array of conditions, and an array of groups) so a
      // malformed write can't leave a row the read path later fails to decode.
      t.column("filter", .text).notNull()
        .check(
          // `IS` (not `=`) so a missing key resolves to FALSE, not NULL — a
          // CHECK passes on NULL, so `= 'text'` would let a row missing the
          // key through.
          sql: """
            json_valid(filter)
            AND json_type(filter) = 'object'
            AND json_type(filter, '$.combinator') IS 'text'
            AND json_type(filter, '$.conditions') IS 'array'
            AND json_type(filter, '$.groups') IS 'array'
            """
        )
      t.column("displayOrder", .integer).notNull()
      t.column("sortMethod", .text).notNull().defaults(to: "newestFirst")
        .check { allowedSortMethods.contains($0) }
      t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    }
    // `->` (not `->>`) so json_array receives real JSON rather than a quoted
    // string; a null or absent nested group becomes an empty groups array.
    try db.execute(
      sql: """
        INSERT INTO smartList_new (id, title, filter, displayOrder, sortMethod, creationDate)
        SELECT
          id,
          title,
          CASE
            WHEN json_type(filter, '$.nested') IS 'object'
              THEN json_remove(
                json_set(filter, '$.groups', json_array(filter -> '$.nested')),
                '$.nested'
              )
            ELSE json_remove(json_set(filter, '$.groups', json_array()), '$.nested')
          END,
          displayOrder,
          sortMethod,
          creationDate
        FROM smartList
        """
    )
    try db.drop(table: "smartList")
    try db.execute(sql: "ALTER TABLE smartList_new RENAME TO smartList")
    try db.create(index: "smartList_on_displayOrder", on: "smartList", columns: ["displayOrder"])
  }
}
