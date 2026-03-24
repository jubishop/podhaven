// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import SavedMacro
import Tagged

struct UnsavedPodcastEmbedding:
  Identifiable,
  Savable,
  VectorStorable
{
  var id: Podcast.ID { podcastId }

  // MARK: - Data

  static let databaseTableName: String = "podcastEmbedding"

  let podcastId: Podcast.ID
  let vector: Data
  let sourceHash: String
  let embeddingRevision: Int
  let dimension: Int

  // MARK: - Stringable / Searchable

  var toString: String { "embedding[\(podcastId)]" }
  var searchableString: String { toString }

}

@Saved<UnsavedPodcastEmbedding>
struct PodcastEmbedding: Saved, VectorStorable {
  // MARK: - Associations

  static let podcast = belongsTo(Podcast.self)

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let podcastId = Column("podcastId")
    static let vector = Column("vector")
    static let sourceHash = Column("sourceHash")
    static let embeddingRevision = Column("embeddingRevision")
    static let dimension = Column("dimension")
    static let creationDate = Column("creationDate")
  }

  // MARK: - Passthroughs

  var podcastId: Podcast.ID { unsaved.podcastId }
  var vector: Data { unsaved.vector }
  var sourceHash: String { unsaved.sourceHash }
  var embeddingRevision: Int { unsaved.embeddingRevision }
  var dimension: Int { unsaved.dimension }
}
