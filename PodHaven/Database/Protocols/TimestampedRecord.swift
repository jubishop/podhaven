// Copyright Justin Bishop, 2025

import Foundation
import GRDB

protocol TimestampedRecord: MutablePersistableRecord {
  var creationDate: Date? { get set }
}

extension TimestampedRecord {
  mutating func willInsert(_ db: Database) throws {
    if creationDate == nil {
      creationDate = try db.transactionDate
    }
  }
}
