// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Tagged

struct Tag: Identifiable, Savable {
  typealias ID = Tagged<Tag, Int64>

  // MARK: - Data

  static let databaseTableName = "tag"

  let id: ID
  let creationDate: Date
  let name: String

  // For creating new tags before insertion (id and creationDate are DB-generated)
  init(name: String) {
    self.id = ID(rawValue: 0)
    self.creationDate = .distantPast
    self.name = name
  }

  // MARK: - Associations

  static let episodeTags = hasMany(EpisodeTag.self)
  static let episodes = hasMany(Episode.self, through: episodeTags, using: EpisodeTag.episode)
  static let podcastTags = hasMany(PodcastTag.self)
  static let podcasts = hasMany(Podcast.self, through: podcastTags, using: PodcastTag.podcast)

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let name = Column("name")
    static let creationDate = Column("creationDate")
  }

  // MARK: - Stringable / Searchable

  var toString: String { name }
  var searchableString: String { name }

  // MARK: - PersistableRecord

  func encode(to container: inout PersistenceContainer) {
    container[Columns.name] = name
  }
}

// MARK: - DerivableRequest

extension DerivableRequest<Tag> {
  func orderedByName() -> Self {
    order { $0.name.collating(.nocase) }
  }
}
