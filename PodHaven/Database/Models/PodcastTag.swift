// Copyright Justin Bishop, 2026

import Foundation
import GRDB

struct PodcastTag: Codable, Equatable, FetchableRecord, Hashable, PersistableRecord, Sendable,
  TableRecord
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

  // MARK: - Tag-IDs Subquery

  // Mirrors `EpisodeTag.tagIDsSelectable` for the podcast side: a correlated
  // subquery that materialises the set of tagIds attached to the current
  // `podcast.id`. Add to a model's `databaseSelection` when its row decoder
  // needs to populate `tagIDs` (see `PodcastWithEpisodeMetadata`). Callers
  // must root the query in the unaliased `podcast` table — the SQL references
  // `"podcast"."id"` literally, so any alias or self-join on Podcast silently
  // breaks the binding at query time as `no such column: podcast.id`.
  static let tagIDsColumnName = "tagIDs"

  static var tagIDsSelectable: any SQLSelectable {
    SQL(
      """
      (SELECT json_group_array("tagId") \
      FROM "podcastTag" \
      WHERE "podcastTag"."podcastId" = "podcast"."id")
      """
    )
    .sqlExpression.forKey(tagIDsColumnName)
  }

  private static let tagIDsDecoder = JSONDecoder()

  static func decodeTagIDs(from row: Row) throws -> Set<Tag.ID> {
    guard let tagIDsJSON: String = row[tagIDsColumnName] else { return [] }
    return Set(try tagIDsDecoder.decode([Tag.ID].self, from: Data(tagIDsJSON.utf8)))
  }
}
