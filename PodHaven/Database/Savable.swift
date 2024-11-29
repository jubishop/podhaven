// Copyright Justin Bishop, 2024

import Foundation
import GRDB

public protocol Savable:
  Codable,
  Hashable,
  FetchableRecord,
  PersistableRecord,
  Sendable
{}

@dynamicMemberLookup
public struct Saved<V>:
  Codable,
  Hashable,
  Identifiable,
  FetchableRecord,
  PersistableRecord,
  Sendable
where V: Savable {
  public var id: Int64
  public var value: V

  public static var databaseTableName: String { V.databaseTableName }

  subscript<T>(dynamicMember keyPath: KeyPath<V, T>) -> T {
    value[keyPath: keyPath]
  }

  subscript<T>(dynamicMember keyPath: WritableKeyPath<V, T>) -> T {
    get { value[keyPath: keyPath] }
    set { value[keyPath: keyPath] = newValue }
  }

  public init(row: GRDB.Row) throws {
    id = row[Column("id")]
    value = try V(row: row)
  }

  public func encode(to container: inout GRDB.PersistenceContainer) throws {
    container[Column("id")] = id
    try value.encode(to: &container)
  }
}
