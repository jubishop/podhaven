// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct EpisodeEmbedding: Codable, Equatable, FetchableRecord, Hashable, PersistableRecord, Sendable,
  TableRecord, VectorStorable
{
  // MARK: - Data

  static let databaseTableName: String = "episodeEmbedding"

  let episodeId: Episode.ID
  let vector: Data
  let sourceHash: String
  let embeddingRevision: Int
  let dimension: Int
  let computedAt: Date

  // MARK: - Associations

  static let episode = belongsTo(Episode.self)

  // MARK: - Columns

  enum Columns {
    static let episodeId = Column("episodeId")
    static let vector = Column("vector")
    static let sourceHash = Column("sourceHash")
    static let embeddingRevision = Column("embeddingRevision")
    static let dimension = Column("dimension")
    static let computedAt = Column("computedAt")
  }

}
