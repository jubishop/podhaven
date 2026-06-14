// Copyright Justin Bishop, 2026

import GRDB

extension Schema {
  static func migrateV59(_ db: Database) throws {
    // Each list sort orders by one of these columns; without an index the
    // ORDER BY ... LIMIT degrades to a full filesort. finishDate/queueDate are
    // partial because the sorts that use them also filter the column non-null,
    // so the index spans only the matching subset and serves filter and order.
    try db.create(index: "episode_on_creationDate", on: "episode", columns: ["creationDate"])
    try db.create(index: "episode_on_duration", on: "episode", columns: ["duration"])
    try db.create(
      index: "episode_on_finishDate",
      on: "episode",
      columns: ["finishDate"],
      condition: Column("finishDate") != nil
    )
    try db.create(
      index: "episode_on_queueDate",
      on: "episode",
      columns: ["queueDate"],
      condition: Column("queueDate") != nil
    )

    // Tag-membership subqueries filter the junction tables by tagId, but their
    // only index is the (…Id, tagId) unique key with tagId trailing, forcing a
    // scan. A tagId-leading index covers the subquery's selected column.
    try db.create(
      index: "episodeTag_on_tagId_episodeId",
      on: "episodeTag",
      columns: ["tagId", "episodeId"]
    )
    try db.create(
      index: "podcastTag_on_tagId_podcastId",
      on: "podcastTag",
      columns: ["tagId", "podcastId"]
    )

    // Replace the rating-only partial index with a (rating, pubDate) composite:
    // it still serves rating-only lookups (rating leads) and additionally serves
    // a pubDate-ordered list within a rating without a separate filesort.
    try db.drop(index: "episode_on_rating")
    try db.create(
      index: "episode_on_rating_pubDate",
      on: "episode",
      columns: ["rating", "pubDate"],
      condition: Column("rating") != nil
    )

    // The startsWith text operator is removed; fold any saved filter using it
    // into contains. JSONEncoder emits compact JSON so the operator token is
    // exact, and a user value containing the literal would be quote-escaped and
    // cannot match this pattern.
    try db.execute(
      sql: """
        UPDATE smartList
        SET filter = REPLACE(filter, '"op":"startsWith"', '"op":"contains"')
        WHERE filter LIKE '%"op":"startsWith"%'
        """
    )

    // Refresh planner statistics so the new and rebuilt indexes are chosen.
    try db.execute(sql: "ANALYZE")
  }
}
