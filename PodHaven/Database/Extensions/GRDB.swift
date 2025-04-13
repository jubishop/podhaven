// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

extension DerivableRequest {
  func shuffled() -> Self {
    order(sql: "RANDOM()")
  }
}

extension FetchRequest where RowDecoder: FetchableRecord & Identifiable {
  public func fetchIdentifiedArray(_ db: Database) throws -> IdentifiedArrayOf<RowDecoder> {
    try IdentifiedArray(uniqueElements: fetchAll(db))
  }

  public func fetchIdentifiedArray<Key: Hashable>(_ db: Database, id: KeyPath<RowDecoder, Key>)
    throws -> IdentifiedArray<Key, RowDecoder>
  {
    try IdentifiedArray(uniqueElements: fetchAll(db), id: id)
  }
}

extension QueryInterfaceRequest {
  func filtered(with sqlExpression: SQLExpression?) -> Self {
    guard let sqlExpression = sqlExpression else { return self }
    return self.filter(sqlExpression)
  }
}

extension TableRecord where Self: Identifiable, Self.ID: DatabaseValueConvertible {
  static func hasManyAnnotation<Destination>(
    _ destination: Destination.Type,
    using foreignKeyColumn: Column? = nil
  ) -> QueryInterfaceRequest<Destination> where Self: Identifiable, Destination: TableRecord {
    let foreignKeyColumn = foreignKeyColumn ?? Column("\(Self.databaseTableName)Id")
    let tableAlias = TableAlias(name: Self.databaseTableName)
    return Destination.filter(foreignKeyColumn == tableAlias[Column("id")])
  }

  static func withID(_ id: ID) -> QueryInterfaceRequest<Self> {
    filter(id: id)
  }
}
