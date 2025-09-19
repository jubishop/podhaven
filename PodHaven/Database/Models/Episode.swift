// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import SavedMacro
import Tagged

typealias GUID = Tagged<UnsavedEpisode, String>
typealias MediaURL = Tagged<UnsavedEpisode, URL>
typealias CachedURL = Tagged<UnsavedEpisode, URL>
struct MediaGUID: Codable, CustomStringConvertible, Equatable, Hashable {
  let guid: GUID
  let mediaURL: MediaURL

  var description: String {
    "GUID: \(guid.toString), MediaURL: \(mediaURL.toString)"
  }
}

struct UnsavedEpisode:
  EpisodeInformable,
  Identifiable,
  Savable,
  Stringable
{
  var id: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }

  private static let log = Log.as(LogSubsystem.Database.episode)

  static let databaseTableName: String = "episode"

  var podcastId: Podcast.ID?

  // Feed
  var guid: GUID
  var mediaURL: MediaURL
  let title: String
  let pubDate: Date
  var duration: CMTime
  let description: String?
  let link: URL?
  let image: URL?

  // User
  let completionDate: Date?
  let currentTime: CMTime
  let queueOrder: Int?
  let lastQueued: Date?
  private let cachedFilename: String?
  let downloadTaskID: URLSessionDownloadTask.ID?

  init(
    podcastId: Podcast.ID? = nil,
    guid: GUID,
    mediaURL: MediaURL,
    title: String,
    pubDate: Date? = nil,
    duration: CMTime? = nil,
    description: String? = nil,
    link: URL? = nil,
    image: URL? = nil,
    completionDate: Date? = nil,
    currentTime: CMTime? = nil,
    queueOrder: Int? = nil,
    lastQueued: Date? = nil,
    cachedFilename: String? = nil,
    downloadTaskID: URLSessionDownloadTask.ID? = nil
  ) throws {
    self.podcastId = podcastId
    self.guid = guid
    self.mediaURL = try mediaURL.convertToHTTPSURL()
    self.title = title
    self.pubDate = pubDate ?? Date()
    self.duration = duration ?? CMTime.zero
    self.description = description
    self.link = try? link?.convertToHTTPSURL()
    self.image = try? image?.convertToHTTPSURL()
    self.completionDate = completionDate
    self.currentTime = currentTime ?? CMTime.zero
    self.queueOrder = queueOrder
    self.lastQueued = lastQueued
    self.cachedFilename = cachedFilename
    self.downloadTaskID = downloadTaskID
  }

  // MARK: - Savable

  var toString: String { "(\(id)) - \(self.title)" }
  var searchableString: String { self.title }

  // MARK: - EpisodeDisplayable / EpisodeInformable

  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }
  var queued: Bool { self.queueOrder != nil }
  var cacheStatus: Episode.CacheStatus {
    if cachedFilename != nil { return .cached }
    if downloadTaskID != nil { return .caching }
    return .uncached
  }
  var started: Bool { self.currentTime.seconds > 0 }
  var finished: Bool { self.completionDate != nil }

  // MARK: - Derived Data

  var cachedURL: CachedURL? {
    guard let cachedFilename = cachedFilename
    else { return nil }

    return CacheManager.resolveCachedFilepath(for: cachedFilename)
  }
}

@Saved<UnsavedEpisode>
struct Episode: EpisodeInformable, Saved, RSSUpdatable {
  // MARK: - Equatable

  static func == (lhs: Episode, rhs: OnDeck) -> Bool { lhs.id == rhs.id }

  // MARK: - Associations

  static let podcast = belongsTo(Podcast.self)
  var podcastID: Podcast.ID { self.podcastId! }

  // MARK: - SQL Expressions

  static let queued: SQLExpression = Episode.Columns.queueOrder != nil
  static let unqueued: SQLExpression = Episode.Columns.queueOrder == nil
  static let cached: SQLExpression = Episode.Columns.cachedFilename != nil
  static let finished: SQLExpression = Episode.Columns.completionDate != nil
  static let unfinished: SQLExpression = Episode.Columns.completionDate == nil
  static let unstarted: SQLExpression = Episode.Columns.currentTime == 0
  static let started: SQLExpression = Episode.Columns.currentTime > 0
  static let previouslyQueued: SQLExpression = Episode.Columns.lastQueued != nil

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let podcastId = Column("podcastId")
    static let guid = Column("guid")
    static let mediaURL = Column("mediaURL")
    static let title = Column("title")
    static let pubDate = Column("pubDate")
    static let duration = Column("duration")
    static let description = Column("description")
    static let link = Column("link")
    static let image = Column("image")
    static let completionDate = Column("completionDate")
    static let currentTime = Column("currentTime")
    static let queueOrder = Column("queueOrder")
    static let lastQueued = Column("lastQueued")
    static let cachedFilename = Column("cachedFilename")
    static let downloadTaskID = Column("downloadTaskID")
    static let creationDate = Column("creationDate")
  }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(ColumnExpression, SQLExpressible)] {
    [
      (Columns.guid, unsaved.guid),
      (Columns.mediaURL, unsaved.mediaURL),
      (Columns.title, unsaved.title),
      (Columns.pubDate, unsaved.pubDate),
      (Columns.description, unsaved.description),
      (Columns.link, unsaved.link),
      (Columns.image, unsaved.image),
    ]
  }

  func rssEquals(_ other: Episode) -> Bool {
    unsaved.guid == other.unsaved.guid
      && unsaved.mediaURL == other.unsaved.mediaURL
      && unsaved.title == other.unsaved.title
      && unsaved.pubDate == other.unsaved.pubDate
      && unsaved.description == other.unsaved.description
      && unsaved.link == other.unsaved.link
      && unsaved.image == other.unsaved.image
  }

  // MARK: - Episode Informable

  var mediaGUID: MediaGUID { unsaved.mediaGUID }
  var title: String { unsaved.title }
  var pubDate: Date { unsaved.pubDate }
  var duration: CMTime { unsaved.duration }
  var description: String? { unsaved.description }
  var queued: Bool { unsaved.queued }
  var queueOrder: Int? { unsaved.queueOrder }
  var started: Bool { unsaved.started }
  var currentTime: CMTime { unsaved.currentTime }
  var finished: Bool { unsaved.finished }

  // MARK: - Derived Passthroughs

  var cacheStatus: CacheStatus { unsaved.cacheStatus }
  var cachedURL: CachedURL? { unsaved.cachedURL }

  // MARK: - Cache Status

  enum CacheStatus: Equatable, Sendable {
    case uncached
    case caching
    case cached
  }
}

// MARK: - DerivableRequest

extension DerivableRequest<Episode> {
  func maxPubDate() -> Self {
    select(max(Episode.Columns.pubDate))
  }

  func cached() -> Self {
    filter(Episode.cached)
  }

  func queued() -> Self {
    filter(Episode.queued)
  }

  func unqueued() -> Self {
    filter(Episode.unqueued)
  }

  func finished() -> Self {
    filter(Episode.finished)
  }

  func unfinished() -> Self {
    filter(Episode.unfinished)
  }

  func started() -> Self {
    filter(Episode.started)
  }

  func unstarted() -> Self {
    filter(Episode.unstarted)
  }
}
