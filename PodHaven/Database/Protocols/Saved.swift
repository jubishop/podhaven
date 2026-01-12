// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Tagged

@dynamicMemberLookup protocol Saved: Savable, Identifiable where ID == Tagged<Self, Int64> {
  associatedtype Unsaved: Savable
  var id: ID { get }
  var creationDate: Date { get }
  var unsaved: Unsaved { get set }
  init(id: ID, creationDate: Date, from unsaved: Unsaved)
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
    self.init(
      id: row[Schema.id],
      creationDate: row[Schema.creationDate],
      from: try Unsaved(row: row)
    )
  }

  // MARK: - PersistableRecord

  public func encode(to container: inout PersistenceContainer) throws {
    container[Schema.id] = id
    container[Schema.creationDate] = creationDate
    try unsaved.encode(to: &container)
  }

  // MARK: - Savable

  public var toString: String { "[\(id)] - \(unsaved.toString)" }
  public var searchableString: String { unsaved.searchableString }
}
