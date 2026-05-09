// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import GRDB
import Tagged

// Slim list-row shape rooted in the Episode table. Mirrors the listable
// subset of `ListablePodcastEpisode` minus the joined Podcast columns —
// callers that already hold the parent `Podcast` (e.g. `PodcastSeriesDetail`)
// fold it in at the view-model layer instead of re-emitting podcast columns
// per row from SQLite.
struct ListableEpisode:
  FetchableRecord, TableRecord, Hashable, Identifiable, Sendable
{
  // Same correlated tag-IDs subquery shape as `ListablePodcastEpisode` —
  // SQLite materialises the JSON array per-row at the projection step, so
  // no LEFT JOIN+GROUP BY blowup against the full filter set.
  static let tagIDsColumnName = "tagIDs"

  static let databaseTableName: String = Episode.databaseTableName
  static var databaseSelection: [any SQLSelectable] {
    [
      Episode.Columns.id,
      Episode.Columns.guid,
      Episode.Columns.mediaURL,
      Episode.Columns.title,
      Episode.Columns.pubDate,
      Episode.Columns.duration,
      Episode.Columns.image,
      Episode.Columns.finishDate,
      Episode.Columns.currentTime,
      Episode.Columns.queueOrder,
      Episode.Columns.saveInCache,
      Episode.Columns.cachedFilename,
      Episode.Columns.downloading,
      Episode.Columns.creationDate,
      Episode.Columns.queueDate,
      Episode.Columns.rating,
      SQL(
        """
        (SELECT json_group_array("tagId") \
        FROM "episodeTag" \
        WHERE "episodeTag"."episodeId" = "episode"."id")
        """
      )
      .sqlExpression.forKey(tagIDsColumnName),
    ]
  }

  // MARK: - Episode Fields

  let id: Episode.ID
  let guid: GUID
  let mediaURL: MediaURL
  let title: String
  let pubDate: Date
  let duration: CMTime
  let episodeImage: URL?
  let finishDate: Date?
  let currentTime: CMTime
  let queueOrder: Int?
  let cacheStatus: Episode.CacheStatus
  let saveInCache: Bool
  let creationDate: Date
  let queueDate: Date?
  let rating: EpisodeRating?
  // Materialised by the correlated subquery in `databaseSelection`. Empty
  // Set means "row exists, no tags".
  let tagIDs: Set<Tag.ID>

  // MARK: - FetchableRecord

  init(row: Row) throws {
    id = row[Episode.Columns.id]
    guid = row[Episode.Columns.guid]
    mediaURL = row[Episode.Columns.mediaURL]
    title = row[Episode.Columns.title]
    pubDate = row[Episode.Columns.pubDate]
    duration = row[Episode.Columns.duration]
    episodeImage = row[Episode.Columns.image]
    finishDate = row[Episode.Columns.finishDate]
    currentTime = row[Episode.Columns.currentTime]
    queueOrder = row[Episode.Columns.queueOrder]
    saveInCache = row[Episode.Columns.saveInCache]
    creationDate = row[Episode.Columns.creationDate]
    queueDate = row[Episode.Columns.queueDate]
    rating = row[Episode.Columns.rating]

    // SQLite's json_group_array returns NULL for an empty group; both an
    // absent column and a NULL value collapse to an empty Set so callers
    // never need to distinguish "no matches" from "no row".
    if let tagIDsJSON: String = row[Self.tagIDsColumnName],
      let data = tagIDsJSON.data(using: .utf8)
    {
      tagIDs = Set(try JSONDecoder().decode([Tag.ID].self, from: data))
    } else {
      tagIDs = []
    }

    cacheStatus = .from(
      cachedFilename: row[Episode.Columns.cachedFilename] as String?,
      downloading: row[Episode.Columns.downloading] as Bool
    )
  }
}
