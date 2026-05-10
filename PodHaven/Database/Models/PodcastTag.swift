// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct PodcastTag:
  Codable,
  Equatable,
  FetchableRecord,
  Hashable,
  PersistableRecord,
  Sendable,
  TableRecord,
  TagJoinableTable
{
  // MARK: - Data

  static let databaseTableName: String = "podcastTag"

  let podcastId: Podcast.ID
  let tagId: Tag.ID

  // MARK: - Associations

  static let podcast = belongsTo(Podcast.self)
  static let tag = belongsTo(Tag.self)

  // MARK: - Columns

  enum Columns {
    static let podcastId = Column("podcastId")
    static let tagId = Column("tagId")
  }

  // MARK: - TagJoinableTable

  static let parentTableName = Podcast.databaseTableName
  static let parentIdColumnName = Columns.podcastId.name
}
