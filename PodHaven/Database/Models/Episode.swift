// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import SavedMacro
import Tagged

typealias GUID = Tagged<UnsavedEpisode, String>
enum MediaURLTag {}
typealias MediaURL = Tagged<MediaURLTag, URL>
enum CachedURLTag {}
typealias CachedURL = Tagged<CachedURLTag, URL>
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
  RSSUpdatable,
  Savable
{
  var id: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }

  private static let log = Log.as(LogSubsystem.Database.episode)

  static let databaseTableName: String = "episode"

  var podcastId: Podcast.ID?

  // Feed
  let guid: GUID
  let mediaURL: MediaURL
  let title: String
  let pubDate: Date
  let duration: CMTime
  let description: String?
  let link: URL?
  let image: URL?

  // User
  let finishDate: Date?
  let currentTime: CMTime
  let queueOrder: Int?
  let queueDate: Date?
  private let cachedFilename: String?
  let downloadTaskID: URLSessionDownloadTask.ID?
  let saveInCache: Bool

  init(
    podcastId: Podcast.ID? = nil,
    guid: GUID,
    mediaURL: MediaURL,
    title: String,
    pubDate: Date?,
    duration: CMTime?,
    description: String?,
    link: URL?,
    image: URL?,
    finishDate: Date? = nil,
    currentTime: CMTime? = nil,
    queueOrder: Int? = nil,
    queueDate: Date? = nil,
    cachedFilename: String? = nil,
    downloadTaskID: URLSessionDownloadTask.ID? = nil,
    saveInCache: Bool = false
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
    self.finishDate = finishDate
    self.currentTime = currentTime ?? CMTime.zero
    self.queueOrder = queueOrder
    self.queueDate = queueDate
    self.cachedFilename = cachedFilename
    self.downloadTaskID = downloadTaskID
    self.saveInCache = saveInCache
  }

  // MARK: - EpisodeInformable

  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }
  var cacheStatus: Episode.CacheStatus {
    if cachedFilename != nil { return .cached }
    if downloadTaskID != nil { return .caching }
    return .uncached
  }

  // MARK: - Derived Data

  // This is effectively a constant so its really plenty safe.
  nonisolated(unsafe) static let timestampRegex =
    /(?:\d{1,2}:\d{2}:\d{2}|\d{1,2}:\d{2})(?![\d:])/

  // Parses timestamps (e.g. "2:15", "14:30", "1:02:15") from the description
  // and returns them as sorted CMTimes. Returns nil if none are found.
  var chapters: [CMTime]? {
    guard let description else { return nil }

    var seen = Set<Int>()
    let times: [CMTime] = unsafe description.matches(of: Self.timestampRegex)
      .compactMap { match in
        // Swift regex doesn't support lookbehind, so manually reject matches
        // preceded by a digit (e.g. "episode123:45" should not match "3:45").
        guard match.range.lowerBound == description.startIndex
          || !description[description.index(before: match.range.lowerBound)].isWholeNumber
        else { return nil }

        // Split "H:MM:SS" or "M:SS" into components and convert to total seconds.
        let components = match.output.split(separator: ":")
        let totalSeconds: Int
        if components.count == 3 {
          guard let hours = Int(components[0]),
            let minutes = Int(components[1]),
            let seconds = Int(components[2])
          else { return nil }
          totalSeconds = hours * 3600 + minutes * 60 + seconds
        } else {
          guard let minutes = Int(components[0]),
            let seconds = Int(components[1])
          else { return nil }
          totalSeconds = minutes * 60 + seconds
        }

        // Skip zero timestamps (episode start) and duplicates.
        guard totalSeconds > 0, seen.insert(totalSeconds).inserted else { return nil }

        // Skip timestamps that exceed the episode duration.
        let time = CMTime.seconds(Double(totalSeconds))
        if time > duration { return nil }

        return time
      }
      .sorted()

    guard !times.isEmpty else { return nil }
    return times
  }

  var cachedURL: CachedURL? {
    guard let cachedFilename = cachedFilename
    else { return nil }

    return CacheManager.resolveCachedFilepath(for: cachedFilename)
  }

  // MARK: - RSSUpdatable

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

  func rssEquals(_ other: UnsavedEpisode) -> Bool {
    guid == other.guid
      && mediaURL == other.mediaURL
      && title == other.title
      && pubDate == other.pubDate
      && description == other.description
      && link == other.link
      && image == other.image
  }

  // MARK: - Reset

  func toOriginalUnsavedEpisode() throws -> UnsavedEpisode {
    try UnsavedEpisode(
      podcastId: podcastId,
      guid: guid,
      mediaURL: mediaURL,
      title: title,
      pubDate: pubDate,
      duration: duration,
      description: description,
      link: link,
      image: image
    )
  }
}

@Saved<UnsavedEpisode>
struct Episode: EpisodeInformable, Saved, RSSUpdatable {
  // MARK: - Stringable / Searchable

  var toString: String { "[\(id)] - \(unsaved.toString)" }
  var searchableString: String { unsaved.searchableString }

  // MARK: - Associations

  static let podcast = belongsTo(Podcast.self)
  var podcastID: Podcast.ID { self.podcastId! }

  // MARK: - SQL Expressions

  static let queued: SQLExpression = Columns.queueOrder != nil
  static let unqueued: SQLExpression = Columns.queueOrder == nil
  static let cached: SQLExpression = Columns.cachedFilename != nil
  static let savedInCache: SQLExpression = cached && Columns.saveInCache == true
  static let finished: SQLExpression = Columns.finishDate != nil
  static let unfinished: SQLExpression = Columns.finishDate == nil
  static let unstarted: SQLExpression = Columns.currentTime == 0
  static let started: SQLExpression = Columns.currentTime > 0
  static let previouslyQueued: SQLExpression = Columns.queueDate != nil
  static func contains(_ pattern: String) -> SQLExpression {
    Columns.title.lowercased.like(pattern) || Columns.description.lowercased.like(pattern)
  }

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
    static let finishDate = Column("finishDate")
    static let currentTime = Column("currentTime")
    static let queueOrder = Column("queueOrder")
    static let queueDate = Column("queueDate")
    static let cachedFilename = Column("cachedFilename")
    static let downloadTaskID = Column("downloadTaskID")
    static let saveInCache = Column("saveInCache")
    static let creationDate = Column("creationDate")
  }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(any ColumnExpression, any SQLExpressible)] {
    unsaved.rssUpdatableColumns
  }

  func rssEquals(_ other: Episode) -> Bool {
    unsaved.rssEquals(other.unsaved)
  }

  // MARK: - EpisodeInformable

  var mediaGUID: MediaGUID { unsaved.mediaGUID }
  var title: String { unsaved.title }
  var pubDate: Date { unsaved.pubDate }
  var description: String? { unsaved.description }
  var duration: CMTime { unsaved.duration }
  var currentTime: CMTime { unsaved.currentTime }
  var queueDate: Date? { unsaved.queueDate }
  var queueOrder: Int? { unsaved.queueOrder }
  var cacheStatus: CacheStatus { unsaved.cacheStatus }
  var saveInCache: Bool { unsaved.saveInCache }
  var finishDate: Date? { unsaved.finishDate }

  // MARK: - Derived Passthroughs
  var cachedURL: CachedURL? { unsaved.cachedURL }

  // MARK: - Reset

  func toOriginalUnsavedEpisode() throws -> UnsavedEpisode {
    try unsaved.toOriginalUnsavedEpisode()
  }

  // MARK: - Cache Status

  enum CacheStatus: Equatable, Sendable {
    case uncached
    case caching
    case cached
  }
}

// MARK: - DerivableRequest

extension DerivableRequest<Episode> {
  func queued() -> Self {
    filter(Episode.queued)
  }

  func unqueued() -> Self {
    filter(Episode.unqueued)
  }

  func cached() -> Self {
    filter(Episode.cached)
  }
}
