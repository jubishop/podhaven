// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Tagged

@dynamicMemberLookup
struct Saved<V>: Savable, Stringable, Identifiable where V: Savable & Stringable {
  public typealias ID = Tagged<Self, Int64>
  public var id: ID
  public var unsaved: V

  subscript<T>(dynamicMember keyPath: KeyPath<V, T>) -> T {
    unsaved[keyPath: keyPath]
  }

  subscript<T>(dynamicMember keyPath: WritableKeyPath<V, T>) -> T {
    get { unsaved[keyPath: keyPath] }
    set { unsaved[keyPath: keyPath] = newValue }
  }

  // MARK: - TableRecord

  public static var databaseTableName: String { V.databaseTableName }

  // MARK: - FetchableRecord

  public init(row: Row) throws {
    id = row[Column(CodingKeys.id)]
    unsaved = try V(row: row)
  }

  public init(id: Tagged<Self, Int64>, from unsaved: V) {
    self.id = id
    self.unsaved = unsaved
  }

  public init(from unsaved: V) {
    self.id = -1
    self.unsaved = unsaved
  }

  // MARK: - PersistableRecord

  public func encode(to container: inout PersistenceContainer) throws {
    container[Column(CodingKeys.id)] = id
    try unsaved.encode(to: &container)
  }

  // MARK: - Savable

  public var toString: String {
    unsaved.toString
  }

  // MARK: - Persistence Callbacks

  public func willDelete(_ db: Database) throws {
    try unsaved.willDelete(db)
  }
  public func willInsert(_ db: Database) throws {
    try unsaved.willInsert(db)
  }
  public func willSave(_ db: Database) throws {
    try unsaved.willSave(db)
  }
  public func willUpdate(_ db: Database, columns: Set<String>) throws {
    try unsaved.willUpdate(db, columns: columns)
  }
  public func didDelete(deleted: Bool) {
    unsaved.didDelete(deleted: deleted)
  }
  public func didInsert(_ inserted: InsertionSuccess) {
    unsaved.didInsert(inserted)
  }
  public func didSave(_ saved: PersistenceSuccess) {
    unsaved.didSave(saved)
  }
  public func didUpdate(_ updated: PersistenceSuccess) {
    unsaved.didUpdate(updated)
  }
  public func aroundDelete(_ db: Database, delete: () throws -> Bool) throws {
    try unsaved.aroundDelete(db, delete: delete)
  }
  public func aroundInsert(
    _ db: Database,
    insert: () throws -> InsertionSuccess
  ) throws {
    try unsaved.aroundInsert(db, insert: insert)
  }
  public func aroundSave(_ db: Database, save: () throws -> PersistenceSuccess)
    throws
  {
    try unsaved.aroundSave(db, save: save)
  }
  public func aroundUpdate(
    _ db: Database,
    columns: Set<String>,
    update: () throws -> PersistenceSuccess
  ) throws {
    try unsaved.aroundUpdate(db, columns: columns, update: update)
  }
}
