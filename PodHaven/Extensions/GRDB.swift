// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

extension DerivableRequest {
  func shuffled() -> Self {
    order(sql: "RANDOM()")
  }
}

extension TableRecord where Self: Identifiable {
  static func withID(_ id: ID) -> QueryInterfaceRequest<Self>
  where Self.ID: DatabaseValueConvertible {
    filter(id: id)
  }

  static func withIDs(_ ids: any Collection<ID>) -> QueryInterfaceRequest<Self>
  where Self.ID: DatabaseValueConvertible {
    filter(ids.contains(Schema.id))
  }
}

extension PersistableRecord {
  func upsertLimitedColumns<U: FetchableRecord>(_ db: Database, columns: [any ColumnExpression])
    throws -> U
  {
    let container = try databaseDictionary

    let columnsSQL = container.map(\.key).joined(separator: ", ")
    let placeholders = Array(repeating: "?", count: container.count).joined(separator: ", ")
    let updateSQL = columns.map { "\($0.name) = excluded.\($0.name)" }.joined(separator: ", ")

    let sql = """
      INSERT INTO \(Self.databaseTableName) (\(columnsSQL))
      VALUES (\(placeholders))
      ON CONFLICT DO UPDATE SET \(updateSQL)
      RETURNING *
      """

    guard
      let result = try U.fetchOne(
        db,
        sql: sql,
        arguments: StatementArguments(container.map(\.value))
      )
    else { throw DatabaseError(message: "Upsert returned no rows") }

    return result
  }
}
