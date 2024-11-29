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

extension Savable {
  static var databaseTableName: String {
    let prefix = "Unsaved"

    let typeName =
      String(describing: Self.self).components(separatedBy: ".").last ?? ""
    guard typeName.hasPrefix(prefix) else {
      fatalError("Struct name: \(typeName) must start with \"\(prefix)\".")
    }

    let suffix = typeName.dropFirst(prefix.count)
    guard let firstCharacter = suffix.first else {
      fatalError("Struct name after '\(prefix)' prefix is empty.")
    }

    let tableName = firstCharacter.lowercased() + suffix.dropFirst()
    return tableName
  }
}

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

  subscript<T>(dynamicMember keyPath: KeyPath<V, T>) -> T {
    value[keyPath: keyPath]
  }

  subscript<T>(dynamicMember keyPath: WritableKeyPath<V, T>) -> T {
    get { value[keyPath: keyPath] }
    set { value[keyPath: keyPath] = newValue }
  }

  // MARK: - TableRecord

  public static var databaseTableName: String { V.databaseTableName }

  // MARK: - FetchableRecord

  public init(row: GRDB.Row) throws {
    id = row[Column("id")]
    value = try V(row: row)
  }

  // MARK: - PersistableRecord

  public func encode(to container: inout GRDB.PersistenceContainer) throws {
    container[Column("id")] = id
    try value.encode(to: &container)
  }
}
