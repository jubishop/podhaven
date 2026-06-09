// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Tagged

extension Container {
  var smartListRepo: Factory<SmartListRepo> {
    Factory(self) { self.makeSmartListRepo() }.scope(.cached)
  }
}

struct SmartListRepo: Sendable {
  private static let log = Log.as(LogSubsystem.Database.repo)

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
    try await writer.write { db in
      try unsaved.insertAndFetch(db, as: SmartList.self)
    }
  }

  @discardableResult
  func updateTitle(_ id: SmartList.ID, to title: String) async throws -> Bool {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw DatabaseError(message: "Smart List title cannot be empty")
    }
    return try await writer.write { db in
      try SmartList.withID(id).updateAll(db, SmartList.Columns.title.set(to: trimmed))
    } > 0
  }

  @discardableResult
  func updateFilter(_ id: SmartList.ID, to filter: SmartListFilter) async throws -> Bool {
    try await writer.write { db in
      try SmartList.withID(id).updateAll(db, SmartList.Columns.filter.set(to: filter.databaseValue))
    } > 0
  }

  @discardableResult
  func updateSortMethod(_ id: SmartList.ID, to sortMethod: SmartListSortMethod) async throws -> Bool
  {
    try await writer.write { db in
      try SmartList
        .withID(id)
        .updateAll(db, SmartList.Columns.sortMethod.set(to: sortMethod.databaseValue))
    } > 0
  }

  @discardableResult
  func delete(_ id: SmartList.ID) async throws -> Bool {
    try await writer.write { db in
      try SmartList.withID(id).deleteAll(db)
    } > 0
  }

  // Renumbers displayOrder into a dense 0-based sequence with `id` moved to
  // `position` (clamped), all in one transaction.
  func moveSmartList(_ id: SmartList.ID, to position: Int) async throws {
    try await writer.write { db in
      var ids =
        try SmartList
        .all()
        .orderedByDisplay()
        .select(SmartList.Columns.id, as: SmartList.ID.self)
        .fetchAll(db)
      guard let from = ids.firstIndex(of: id) else { return }
      ids.remove(at: from)
      ids.insert(id, at: max(0, min(position, ids.count)))
      for (index, rowID) in ids.enumerated() {
        try SmartList
          .withID(rowID)
          .updateAll(db, SmartList.Columns.displayOrder.set(to: index))
      }
    }
  }
}
