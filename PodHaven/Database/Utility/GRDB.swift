// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import IdentifiedCollections

extension DerivableRequest {
  func shuffled() -> Self {
    order(sql: "RANDOM()")
  }
}

extension FetchRequest where RowDecoder: FetchableRecord & Identifiable {
  public func fetchIdentifiedArray(_ db: Database)
    throws -> IdentifiedArrayOf<RowDecoder>
  {
    try IdentifiedArray(fetchCursor(db))
  }
}
