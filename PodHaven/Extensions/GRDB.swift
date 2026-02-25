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

extension FetchRequest where RowDecoder: FetchableRecord & Identifiable {
  // Returns an identified array of fetched records.
  func fetchIdentifiedArray(_ db: Database) throws -> IdentifiedArrayOf<RowDecoder> {
    try IdentifiedArray(fetchCursor(db))
  }
}
