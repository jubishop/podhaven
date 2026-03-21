// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct PodcastEmbedding: Codable, Equatable, FetchableRecord, Hashable, PersistableRecord, Sendable,
  TableRecord
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

  // MARK: - Vector Conversion

  var floatVector: [Float] {
    do {
      return try JSONDecoder().decode([Float].self, from: vector)
    } catch {
      Assert.fatal("Failed to decode podcast embedding vector: \(error)")
    }
  }

  static func vectorData(from floats: [Float]) -> Data {
    do {
      return try JSONEncoder().encode(floats)
    } catch {
      Assert.fatal("Failed to encode podcast embedding vector: \(error)")
    }
  }
}
