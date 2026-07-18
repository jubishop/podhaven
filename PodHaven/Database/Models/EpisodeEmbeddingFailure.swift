// Copyright Justin Bishop, 2026

import GRDB

struct EpisodeEmbeddingFailure:
  Codable,
  Equatable,
  FetchableRecord,
  PersistableRecord,
  Sendable,
  TableRecord
{
  static let databaseTableName = "episodeEmbeddingFailure"

  let episodeId: Episode.ID
  let episodeContentUpdatedAt: String
  let podcastContentUpdatedAt: String
  let embeddingRevision: Int
  let recipeVersion: Int
  let attemptCount: Int

  static let episode = belongsTo(Episode.self)

  enum Columns {
    static let episodeId = Column("episodeId")
    static let episodeContentUpdatedAt = Column("episodeContentUpdatedAt")
    static let podcastContentUpdatedAt = Column("podcastContentUpdatedAt")
    static let embeddingRevision = Column("embeddingRevision")
    static let recipeVersion = Column("recipeVersion")
    static let attemptCount = Column("attemptCount")
  }
}
