// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import GRDB

struct FeedMergeEpisode: FetchableRecord, Identifiable, RSSUpdatable, Sendable, TableRecord {
  static let databaseTableName: String = Episode.databaseTableName
  static var databaseSelection: [any SQLSelectable] {
    [
      Episode.Columns.id,
      Episode.Columns.guid,
      Episode.Columns.mediaURL,
      Episode.Columns.title,
      Episode.Columns.pubDate,
      Episode.Columns.duration,
      Episode.Columns.description,
      Episode.Columns.link,
      Episode.Columns.image,
    ]
  }

  let id: Episode.ID
  let guid: GUID
  let mediaURL: MediaURL
  let title: String
  let pubDate: Date
  let duration: CMTime
  let description: String?
  let link: URL?
  let image: URL?

  init(id: Episode.ID, from episode: UnsavedEpisode) {
    self.id = id
    self.guid = episode.guid
    self.mediaURL = episode.mediaURL
    self.title = episode.title
    self.pubDate = episode.pubDate
    self.duration = episode.duration
    self.description = episode.description
    self.link = episode.link
    self.image = episode.image
  }

  init(row: Row) throws {
    id = row[Episode.Columns.id]
    guid = row[Episode.Columns.guid]
    mediaURL = row[Episode.Columns.mediaURL]
    title = row[Episode.Columns.title]
    pubDate = row[Episode.Columns.pubDate]
    duration = row[Episode.Columns.duration]
    description = row[Episode.Columns.description]
    link = row[Episode.Columns.link]
    image = row[Episode.Columns.image]
  }

  var rssUpdatableColumns: [(any ColumnExpression, any SQLExpressible)] {
    [
      (Episode.Columns.guid, guid),
      (Episode.Columns.mediaURL, mediaURL),
      (Episode.Columns.title, title),
      (Episode.Columns.pubDate, pubDate),
      (Episode.Columns.description, description),
      (Episode.Columns.link, link),
      (Episode.Columns.image, image),
    ]
  }

  func rssEquals(_ other: FeedMergeEpisode) -> Bool {
    guid == other.guid
      && mediaURL == other.mediaURL
      && title == other.title
      && pubDate == other.pubDate
      && description == other.description
      && link == other.link
      && image == other.image
  }
}
