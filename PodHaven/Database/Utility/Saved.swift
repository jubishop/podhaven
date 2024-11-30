// Copyright Justin Bishop, 2024

import Foundation
import GRDB

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
  private var value: V

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

  public init(row: Row) throws {
    id = row[Column("id")]
    value = try V(row: row)
  }

  // MARK: - PersistableRecord

  public func encode(to container: inout PersistenceContainer) throws {
    container[Column("id")] = id
    try value.encode(to: &container)
  }

  // MARK: - Persistence Callbacks

  public func willDelete(_ db: Database) throws {
    try value.willDelete(db)
  }
  public func willInsert(_ db: Database) throws {
    try value.willInsert(db)
  }
  public func willSave(_ db: Database) throws {
    try value.willSave(db)
  }
  public func willUpdate(_ db: Database, columns: Set<String>) throws {
    try value.willUpdate(db, columns: columns)
  }
  public func didDelete(deleted: Bool) {
    value.didDelete(deleted: deleted)
  }
  public func didInsert(_ inserted: InsertionSuccess) {
    value.didInsert(inserted)
  }
  public func didSave(_ saved: PersistenceSuccess) {
    value.didSave(saved)
  }
  public func didUpdate(_ updated: PersistenceSuccess) {
    value.didUpdate(updated)
  }
  public func aroundDelete(_ db: Database, delete: () throws -> Bool) throws {
    try value.aroundDelete(db, delete: delete)
  }
  public func aroundInsert(
    _ db: Database,
    insert: () throws -> InsertionSuccess
  ) throws {
    try value.aroundInsert(db, insert: insert)
  }
  public func aroundSave(_ db: Database, save: () throws -> PersistenceSuccess)
    throws
  {
    try value.aroundSave(db, save: save)
  }
  public func aroundUpdate(
    _ db: Database,
    columns: Set<String>,
    update: () throws -> PersistenceSuccess
  ) throws {
    try value.aroundUpdate(db, columns: columns, update: update)
  }
}
