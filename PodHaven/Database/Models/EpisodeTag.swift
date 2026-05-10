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
  TableRecord
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

  // MARK: - Tag-IDs Subquery

  // Column key under which the correlated tag-IDs subquery is materialised
  // by row-decoding models that carry `tagIDs` as a stored field. Kept as
  // a single literal so query authors and row decoders agree on the name.
  static let tagIDsColumnName = "tagIDs"

  // Correlated subquery that materialises the set of tagIds attached to
  // the current `episode.id`. Add to a model's `databaseSelection` when
  // its row decoder needs to populate `tagIDs` (see `ListableEpisode`,
  // `OnDeck`). Callers must root the query in the unaliased `episode`
  // table — the SQL references `"episode"."id"` literally, so any alias
  // or self-join on Episode silently breaks the binding at query time
  // as `no such column: episode.id`.
  static var tagIDsSelectable: any SQLSelectable {
    SQL(
      """
      (SELECT json_group_array("tagId") \
      FROM "episodeTag" \
      WHERE "episodeTag"."episodeId" = "episode"."id")
      """
    )
    .sqlExpression.forKey(tagIDsColumnName)
  }

  // Reused across every row decode — `init(row:)` is hot for list rows
  // and observation re-fires; a per-row `JSONDecoder()` adds allocator
  // pressure for no benefit.
  private static let tagIDsDecoder = JSONDecoder()

  static func decodeTagIDs(from row: Row) throws -> Set<Tag.ID> {
    guard let tagIDsJSON: String = row[tagIDsColumnName] else { return [] }
    return Set(try tagIDsDecoder.decode([Tag.ID].self, from: Data(tagIDsJSON.utf8)))
  }
}
