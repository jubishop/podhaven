// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Conformers expose a correlated `tagIDs` subquery for `databaseSelection`
// plus a matching row decoder. The subquery references the parent table by
// literal name, so aliasing or self-joining the parent breaks at query time.
protocol TagJoinableTable: TableRecord {
  static var parentTableName: String { get }
  static var parentIdColumnName: String { get }
}

extension TagJoinableTable {
  static var tagIDsColumnName: String { "tagIDs" }

  static var tagIDsSelectable: any SQLSelectable {
    SQL(
      """
      (SELECT json_group_array("tagId") \
      FROM "\(sql: databaseTableName)" \
      WHERE "\(sql: databaseTableName)"."\(sql: parentIdColumnName)" \
        = "\(sql: parentTableName)"."id")
      """
    )
    .sqlExpression.forKey(tagIDsColumnName)
  }

  static func decodeTagIDs(from row: Row) throws -> Set<Tag.ID> {
    guard let tagIDsJSON: String = row[tagIDsColumnName] else {
      Assert.fatal("\(Self.self) requires tagIDs selection")
    }
    return Set(
      try TagJoinableTableDecoder.shared.decode([Tag.ID].self, from: Data(tagIDsJSON.utf8))
    )
  }
}

// One shared decoder — `init(row:)` is hot under list rendering and
// observation re-fires.
private enum TagJoinableTableDecoder {
  static let shared = JSONDecoder()
}
