// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

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

extension DerivableRequest {
  func shuffled() -> Self {
    order(sql: "RANDOM()")
  }
}

extension TableRecord where Self: Identifiable {
  static func hasManySubquery<Destination: TableRecord>(
    _ destination: Destination.Type,
    using foreignKeyColumn: Column = Column("\(Self.databaseTableName)Id")
  ) -> QueryInterfaceRequest<Destination> {
    let tableAlias = TableAlias(name: Self.databaseTableName)
    return Destination.filter(foreignKeyColumn == tableAlias[Column("id")])
  }

  static func withID(_ id: ID) -> QueryInterfaceRequest<Self>
  where Self.ID: DatabaseValueConvertible {
    filter(id: id)
  }
}
