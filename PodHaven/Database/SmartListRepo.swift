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

  @discardableResult
  func updateTitle(_ id: SmartList.ID, to title: String) async throws -> Bool {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw DatabaseError(message: "Smart List title cannot be empty")
    }
    Self.log.debug("updateTitle: \(id) to \(trimmed)")

    return try await writer.write { db in
      try SmartList.withID(id).updateAll(db, SmartList.Columns.title.set(to: trimmed))
    } > 0
  }

  @discardableResult
  func updateFilter(_ id: SmartList.ID, to filter: SmartListFilter) async throws -> Bool {
    Self.log.debug(
      "updateFilter: \(id) to \(filter.conditions.count) conditions (nested: \(filter.nested != nil))"
    )

    return try await writer.write { db in
      try SmartList.withID(id).updateAll(db, SmartList.Columns.filter.set(to: filter.databaseValue))
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

  // MARK: - Legacy Sort Preference Cleanup

  // One-time cleanup after the UI swap to row-persisted sort. A surviving
  // legacy key holds the newest pre-upgrade sort pick (sort changes made after
  // the v54 copy landed only in UserDefaults), so re-copy each onto its
  // matching row by title, then delete the key. Title matching is reliable
  // because lists couldn't be renamed before the editor shipped. No-ops once
  // the keys are gone; a failed row write keeps its key for a retry next launch.
  func migrateLegacySortPreferences() async {
    let store = Container.shared.standardDefaults()
    let prefix = "EpisodesList-sortMethod-"
    let keys = store.allKeys.filter { $0.hasPrefix(prefix) }
    guard !keys.isEmpty else { return }
    Self.log.info("migrateLegacySortPreferences: cleaning up \(keys.count) legacy sort keys")

    var rowIDsByTitle: [String: SmartList.ID] = [:]
    do {
      for smartList in try await fetchAll() where rowIDsByTitle[smartList.title] == nil {
        rowIDsByTitle[smartList.title] = smartList.id
      }
    } catch {
      Self.log.caughtError("migrateLegacySortPreferences: failed to fetch smart lists", error)
      return
    }

    for key in keys {
      let title = String(key.dropFirst(prefix.count))
      if let id = rowIDsByTitle[title], let sortMethod = Self.decodeLegacySortMethod(store, key) {
        do {
          try await updateSortMethod(id, to: sortMethod)
        } catch {
          Self.log.caughtError(
            "migrateLegacySortPreferences: failed to copy '\(title)' sort onto its row",
            error
          )
          continue
        }
      }
      store.removeObject(forKey: key)
    }
  }

  private static func decodeLegacySortMethod(
    _ store: any KeyValueStore,
    _ key: String
  ) -> SmartListSortMethod? {
    guard let data = store.data(forKey: key) else { return nil }
    do {
      return try JSONDecoder().decode(SmartListSortMethod.self, from: data)
    } catch {
      Self.log.caughtError("decodeLegacySortMethod: undecodable value for '\(key)'", error)
      return nil
    }
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
