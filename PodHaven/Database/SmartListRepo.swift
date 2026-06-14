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
      // Start "fully seen" so a freshly created list reads as zero unread.
      var toInsert = unsaved
      toInsert.lastSeenEpisodeId = try Self.maxEpisodeID(db)
      return try toInsert.insertAndFetch(db, as: SmartList.self)
    }
  }

  // Advances the unread-badge watermark to the newest episode id, clearing the
  // list's badge. Called when the user leaves the list.
  func markSeen(_ id: SmartList.ID) async throws {
    Self.log.debug("markSeen: \(id)")

    try await writer.write { db in
      let watermark = try Self.maxEpisodeID(db)
      _ =
        try SmartList
        .withID(id)
        .updateAll(db, SmartList.Columns.lastSeenEpisodeId.set(to: watermark))
    }
  }

  // Title, filter, and artwork preference land in one transaction so a save
  // can't half-apply.
  @discardableResult
  func update(
    _ id: SmartList.ID,
    title: String,
    filter: SmartListFilter,
    alwaysShowPodcastImage: Bool
  ) async throws -> Bool {
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
      // A changed filter redefines membership, so its badge starts over: stamp
      // the watermark to "now" alongside the edit. Title/artwork-only edits keep
      // the existing watermark so the badge survives a rename.
      let existingFilter =
        try SmartList
        .withID(id)
        .select(SmartList.Columns.filter, as: SmartListFilter.self)
        .fetchOne(db)

      var assignments: [ColumnAssignment] = [
        SmartList.Columns.title.set(to: trimmed),
        SmartList.Columns.filter.set(to: filter.databaseValue),
        SmartList.Columns.alwaysShowPodcastImage.set(to: alwaysShowPodcastImage),
      ]
      if existingFilter != filter {
        assignments.append(
          SmartList.Columns.lastSeenEpisodeId.set(to: try Self.maxEpisodeID(db))
        )
      }

      return try SmartList.withID(id).updateAll(db, assignments)
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

  // MARK: - Private Helpers

  // The newest episode id, or 0 when the library is empty. Used as the unread-
  // badge watermark on insert / markSeen / filter change.
  private static func maxEpisodeID(_ db: Database) throws -> Episode.ID {
    try Episode.select(max(Episode.Columns.id), as: Episode.ID.self).fetchOne(db) ?? 0
  }
}
