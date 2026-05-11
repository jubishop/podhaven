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
  EpisodeFoundational,
  FetchableRecord,
  Hashable,
  Identifiable,
  Sendable,
  TableRecord
{
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
      EpisodeTag.tagIDsSelectable,
    ]
  }

  // MARK: - Episode Fields

  let id: Episode.ID
  var episodeID: Episode.ID? { id }
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

    tagIDs = try EpisodeTag.decodeTagIDs(from: row)

    cacheStatus = .from(
      cachedFilename: row[Episode.Columns.cachedFilename] as String?,
      downloading: row[Episode.Columns.downloading] as Bool
    )
  }
}
