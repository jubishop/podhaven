// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import SavedMacro
import Tagged

struct UnsavedSmartList: Identifiable, Savable {
  // MARK: - Identifiable

  // An unsaved row has no database id yet, so the value is its own identity.
  var id: Self { self }

  // MARK: - Data

  static let databaseTableName: String = "smartList"

  // `let` so the init's trim/blank guard can't be bypassed by later mutation.
  let title: String
  var filter: SmartListFilter
  var displayOrder: Int
  var sortMethod: SmartListSortMethod
  // When true the list always shows podcast artwork; when false it shows the
  // episode-specific artwork when one exists. Mirrors the per-Queue setting.
  var alwaysShowPodcastImage: Bool
  var icon: LucideIcon
  // Unread-badge watermark: the highest episode id this list has "seen". A high-
  // water threshold, not a live reference (the episode may later be deleted; the
  // AUTOINCREMENT id is never reused). Repo-managed, not user-editable. 0 means
  // nothing seen yet, so every episode (ids start at 1) counts as new.
  var lastSeenEpisodeId: Episode.ID

  init(
    title: String,
    filter: SmartListFilter,
    displayOrder: Int,
    sortMethod: SmartListSortMethod = .newestFirst,
    alwaysShowPodcastImage: Bool = false,
    icon: LucideIcon = .listMusic,
    lastSeenEpisodeId: Episode.ID = 0
  ) throws {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw DatabaseError(message: "Smart List title cannot be empty")
    }
    self.title = trimmed
    self.filter = filter
    self.displayOrder = displayOrder
    self.sortMethod = sortMethod
    self.alwaysShowPodcastImage = alwaysShowPodcastImage
    self.icon = icon
    self.lastSeenEpisodeId = lastSeenEpisodeId
  }

  // MARK: - Stringable / Searchable

  var toString: String { title }
  var searchableString: String { title }
}

@Saved<UnsavedSmartList>
struct SmartList: Saved {
  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let title = Column("title")
    static let filter = Column("filter")
    static let displayOrder = Column("displayOrder")
    static let sortMethod = Column("sortMethod")
    static let alwaysShowPodcastImage = Column("alwaysShowPodcastImage")
    static let icon = Column("icon")
    static let lastSeenEpisodeId = Column("lastSeenEpisodeId")
    static let creationDate = Column("creationDate")
  }

  // MARK: - Derived Passthroughs

  var title: String { unsaved.title }
  var filter: SmartListFilter { unsaved.filter }
  var displayOrder: Int { unsaved.displayOrder }
  var sortMethod: SmartListSortMethod { unsaved.sortMethod }
  var alwaysShowPodcastImage: Bool { unsaved.alwaysShowPodcastImage }
  var icon: LucideIcon { unsaved.icon }
  var lastSeenEpisodeId: Episode.ID { unsaved.lastSeenEpisodeId }
}

// MARK: - DerivableRequest

extension DerivableRequest<SmartList> {
  func orderedByDisplay() -> Self {
    order(SmartList.Columns.displayOrder.asc, SmartList.Columns.id.asc)
  }
}
