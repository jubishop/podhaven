// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import SavedMacro
import Tagged

struct UnsavedEpisodeEmbedding:
  Identifiable,
  Savable,
  VectorStorable
{
  var id: Episode.ID { episodeId }

  // MARK: - Data

  static let databaseTableName: String = "episodeEmbedding"

  let episodeId: Episode.ID
  let vector: Data
  let sourceHash: String
  let embeddingRevision: Int
  let dimension: Int

  // MARK: - Stringable / Searchable

  var toString: String { "embedding[\(episodeId)]" }
  var searchableString: String { toString }
}

@Saved<UnsavedEpisodeEmbedding>
struct EpisodeEmbedding: Saved, VectorStorable {
  // MARK: - Associations

  static let episode = belongsTo(Episode.self)

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let episodeId = Column("episodeId")
    static let vector = Column("vector")
    static let sourceHash = Column("sourceHash")
    static let embeddingRevision = Column("embeddingRevision")
    static let dimension = Column("dimension")
    static let creationDate = Column("creationDate")
  }

  // MARK: - Passthroughs

  var episodeId: Episode.ID { unsaved.episodeId }
  var vector: Data { unsaved.vector }
  var sourceHash: String { unsaved.sourceHash }
  var embeddingRevision: Int { unsaved.embeddingRevision }
  var dimension: Int { unsaved.dimension }
}
