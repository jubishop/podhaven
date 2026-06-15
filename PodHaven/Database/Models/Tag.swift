// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import SavedMacro
import Tagged

struct UnsavedTag: Identifiable, Savable {
  // MARK: - Identifiable

  var id: String { name }

  // MARK: - Data

  static let databaseTableName: String = "tag"

  let name: String
  var icon: LucideIcon

  init(name: String, icon: LucideIcon = .tag) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw DatabaseError(message: "Tag name cannot be empty")
    }
    self.name = trimmed
    self.icon = icon
  }

  // MARK: - Stringable / Searchable

  var toString: String { name }
  var searchableString: String { name }
}

@Saved<UnsavedTag>
struct Tag: Saved {
  // MARK: - Associations

  static let episodeTags = hasMany(EpisodeTag.self)
  static let episodes = hasMany(Episode.self, through: episodeTags, using: EpisodeTag.episode)
  static let podcastTags = hasMany(PodcastTag.self)
  static let podcasts = hasMany(Podcast.self, through: podcastTags, using: PodcastTag.podcast)

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let name = Column("name")
    static let icon = Column("icon")
    static let creationDate = Column("creationDate")
  }

  // MARK: - Derived Passthroughs

  var name: String { unsaved.name }
  var icon: LucideIcon { unsaved.icon }
}

// MARK: - DerivableRequest

extension DerivableRequest<Tag> {
  func orderedByName() -> Self {
    order { $0.name.collating(.nocase) }
  }
}
