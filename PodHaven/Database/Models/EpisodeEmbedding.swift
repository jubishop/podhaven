// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct EpisodeEmbedding: Codable, Equatable, FetchableRecord, Hashable, PersistableRecord, Sendable,
  TableRecord
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

  // MARK: - Vector Conversion

  var floatVector: [Float] {
    do {
      return try JSONDecoder().decode([Float].self, from: vector)
    } catch {
      Assert.fatal("Failed to decode episode embedding vector: \(error)")
    }
  }

  static func vectorData(from floats: [Float]) -> Data {
    do {
      return try JSONEncoder().encode(floats)
    } catch {
      Assert.fatal("Failed to encode episode embedding vector: \(error)")
    }
  }
}
