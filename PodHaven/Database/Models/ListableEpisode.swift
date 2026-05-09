// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import GRDB
import Tagged

// Slim list-row shape rooted in the Episode table — the Episode-side
// projection of `ListablePodcastEpisode` minus the joined Podcast columns.
// Both list types share `databaseSelection` and `init(row:)` from here so
// the Episode-side column list, correlated tag-IDs subquery, and row decode
// live in exactly one place. Callers that already hold the parent `Podcast`
// (e.g. `PodcastSeriesDetail`) fold it in at the view-model layer instead
// of re-emitting podcast columns per row from SQLite.
struct ListableEpisode:
  EpisodeFoundational, FetchableRecord, TableRecord, Hashable, Identifiable, Sendable
{
  // Column key under which the correlated tag-IDs subquery is materialised.
  // Kept as a literal so observation tests and the row decoder agree on the
  // column name without coupling to a model property.
  static let tagIDsColumnName = "tagIDs"

  // Reused across every row decode — `init(row:)` is hot on long lists,
  // and a per-row `JSONDecoder()` adds allocator pressure for no benefit.
  private static let tagIDsDecoder = JSONDecoder()

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
  let tagIDs: Set<Tag.ID>

  // MARK: - EpisodeFoundational

  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }

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

    if let tagIDsJSON: String = row[Self.tagIDsColumnName],
      let data = tagIDsJSON.data(using: .utf8)
    {
      tagIDs = Set(try Self.tagIDsDecoder.decode([Tag.ID].self, from: data))
    } else {
      tagIDs = []
    }

    cacheStatus = .from(
      cachedFilename: row[Episode.Columns.cachedFilename] as String?,
      downloading: row[Episode.Columns.downloading] as Bool
    )
  }
}
