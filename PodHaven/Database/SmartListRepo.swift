// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging
import Tagged

extension Container {
  var smartListRepo: Factory<SmartListRepo> {
    Factory(self) { self.makeSmartListRepo() }.scope(.cached)
  }
}

struct SmartListRepo: Sendable {
  private static let log = Log.as(LogSubsystem.Database.smartListRepo)

  // MARK: - Initialization

  private let reader: AppDB.Reader
  private let writer: AppDB.Writer
  init(reader: AppDB.Reader, writer: AppDB.Writer) {
    self.reader = reader
    self.writer = writer
  }

  // MARK: - Reads

  func fetchAll() async throws -> [SmartList] {
    try await reader.read { db in
      try SmartList.all().orderedByDisplay().fetchAll(db)
    }
  }

  func fetchOne(_ id: SmartList.ID) async throws -> SmartList? {
    try await reader.read { db in
      try SmartList.withID(id).fetchOne(db)
    }
  }

  // MARK: - Writes

  func insert(_ unsaved: UnsavedSmartList) async throws -> SmartList {
    Self.log.debug("insert: \(unsaved.title)")

    return try await writer.write { db in
      try unsaved.insertAndFetch(db, as: SmartList.self)
    }
  }

  // Title and filter land in one transaction so a save can't half-apply.
  @discardableResult
  func update(_ id: SmartList.ID, title: String, filter: SmartListFilter) async throws -> Bool {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw DatabaseError(message: "Smart List title cannot be empty")
    }
    Self.log.debug(
      """
      update: \(id) to '\(trimmed)' with \(filter.conditions.count) conditions \
      and \(filter.groups.count) groups
      """
    )

    return try await writer.write { db in
      try SmartList
        .withID(id)
        .updateAll(
          db,
          SmartList.Columns.title.set(to: trimmed),
          SmartList.Columns.filter.set(to: filter.databaseValue)
        )
    } > 0
  }

  @discardableResult
  func updateSortMethod(_ id: SmartList.ID, to sortMethod: SmartListSortMethod) async throws -> Bool
  {
    Self.log.debug("updateSortMethod: \(id) to \(sortMethod.rawValue)")

    return try await writer.write { db in
      try SmartList
        .withID(id)
        .updateAll(db, SmartList.Columns.sortMethod.set(to: sortMethod.databaseValue))
    } > 0
  }

  @discardableResult
  func delete(_ id: SmartList.ID) async throws -> Bool {
    Self.log.debug("delete: \(id)")

    return try await writer.write { db in
      try SmartList.withID(id).deleteAll(db)
    } > 0
  }

  // Renumbers displayOrder into a dense 0-based sequence after moving `id`.
  // `position` is the destination offset from the original order.
  func moveSmartList(_ id: SmartList.ID, to position: Int) async throws {
    Self.log.debug("moveSmartList: \(id) to position \(position)")

    try await writer.write { db in
      var ids =
        try SmartList
        .all()
        .orderedByDisplay()
        .select(SmartList.Columns.id, as: SmartList.ID.self)
        .fetchAll(db)
      guard let from = ids.firstIndex(of: id) else { return }
      let destination = position > from ? position - 1 : position
      ids.remove(at: from)
      ids.insert(id, at: max(0, min(destination, ids.count)))
      for (index, rowID) in ids.enumerated() {
        try SmartList
          .withID(rowID)
          .updateAll(db, SmartList.Columns.displayOrder.set(to: index))
      }
    }
  }
}
