// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct EpisodeTag:
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

  static let databaseTableName: String = "episodeTag"

  let episodeId: Episode.ID
  let tagId: Tag.ID

  // MARK: - Associations

  static let episode = belongsTo(Episode.self)
  static let tag = belongsTo(Tag.self)

  // MARK: - Columns

  enum Columns {
    static let episodeId = Column("episodeId")
    static let tagId = Column("tagId")
  }

  // MARK: - TagJoinableTable

  static let parentTableName = Episode.databaseTableName
  static let parentIdColumnName = Columns.episodeId.name
}
