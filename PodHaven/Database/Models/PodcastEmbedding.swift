// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct PodcastEmbedding: Codable, Equatable, FetchableRecord, Hashable, PersistableRecord, Sendable,
  TableRecord, VectorStorable
{
  // MARK: - Data

  static let databaseTableName: String = "podcastEmbedding"

  let podcastId: Podcast.ID
  let vector: Data
  let sourceHash: String
  let embeddingRevision: Int
  let dimension: Int
  let computedAt: Date

  // MARK: - Associations

  static let podcast = belongsTo(Podcast.self)

  // MARK: - Columns

  enum Columns {
    static let podcastId = Column("podcastId")
    static let vector = Column("vector")
    static let sourceHash = Column("sourceHash")
    static let embeddingRevision = Column("embeddingRevision")
    static let dimension = Column("dimension")
    static let computedAt = Column("computedAt")
  }

}
