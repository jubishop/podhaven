// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Tagged

@dynamicMemberLookup
protocol Saved: Savable, Identifiable where ID == Tagged<Self, Int64> {
  associatedtype Unsaved: Savable
  var id: ID { get set }
  var unsaved: Unsaved { get set }
  init(id: ID, from unsaved: Unsaved)
}

extension Saved {
  subscript<T>(dynamicMember keyPath: KeyPath<Unsaved, T>) -> T {
    unsaved[keyPath: keyPath]
  }

  subscript<T>(dynamicMember keyPath: WritableKeyPath<Unsaved, T>) -> T {
    get { unsaved[keyPath: keyPath] }
    set { unsaved[keyPath: keyPath] = newValue }
  }

  // MARK: - TableRecord

  public static var databaseTableName: String { Unsaved.databaseTableName }

  // MARK: - FetchableRecord

  public init(row: Row) throws {
    self.init(id: row[Schema.id], from: try Unsaved(row: row))
  }

  public init(from unsaved: Unsaved) {
    self.init(id: -1, from: unsaved)
  }

  // MARK: - PersistableRecord

  public func encode(to container: inout PersistenceContainer) throws {
    container[Schema.id] = id
    try unsaved.encode(to: &container)
  }

  // MARK: - Savable

  public var toString: String {
    unsaved.toString
  }
}
