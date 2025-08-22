// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import SavedMacro
import Tagged

typealias GUID = Tagged<UnsavedEpisode, String>
typealias MediaURL = Tagged<UnsavedEpisode, URL>

struct UnsavedEpisode:
  EpisodeFilterable,
  EpisodeDisplayable,
  Savable,
  Stringable
{
  var id: MediaURL { media }

  private static let log = Log.as(LogSubsystem.Database.episode)

  static let databaseTableName: String = "episode"

  var podcastId: Podcast.ID?
  var guid: GUID
  var media: MediaURL
  let title: String
  let pubDate: Date
  var duration: CMTime
  let description: String?
  let link: URL?
  let image: URL?
  let completionDate: Date?
  let currentTime: CMTime
  let queueOrder: Int?
  let lastQueued: Date?
  let cachedFilename: String?

  init(
    podcastId: Podcast.ID? = nil,
    guid: GUID,
    media: MediaURL,
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
    cachedFilename: String? = nil
  ) throws {
    self.podcastId = podcastId
    self.guid = guid
    self.media = MediaURL(try media.rawValue.convertToValidURL())
    self.title = title
    self.pubDate = pubDate ?? Date()
    self.duration = duration ?? CMTime.zero
    self.description = description
    self.link = try? link?.convertToValidURL()
    self.image = try? image?.convertToValidURL()
    self.completionDate = completionDate
    self.currentTime = currentTime ?? CMTime.zero
    self.queueOrder = queueOrder
    self.lastQueued = lastQueued
    self.cachedFilename = cachedFilename
  }

  // MARK: - Savable

  var toString: String { "(\(media.toString)) - \(self.title)" }
  var searchableString: String { self.title }

  // MARK: - EpisodeDisplayable

  var cached: Bool { self.cachedFilename != nil }
  var completed: Bool { self.completionDate != nil }

  // MARK: - State Getters

  var queued: Bool { self.queueOrder != nil }
  var started: Bool { self.currentTime.seconds > 0 }

  // MARK: - Derived Data

  var mediaURL: URL {
    guard let cachedFilename = cachedFilename
    else { return media.rawValue }

    return CacheManager.resolveCachedFilepath(for: cachedFilename)
  }
}

@Saved<UnsavedEpisode>
struct Episode: EpisodeDisplayable, EpisodeFilterable, Saved, RSSUpdatable {
  // MARK: - Equatable

  static func == (lhs: Episode, rhs: OnDeck) -> Bool { lhs.id == rhs.id }

  // MARK: - Associations

  static let podcast = belongsTo(Podcast.self)
  var podcastID: Podcast.ID { self.podcastId! }

  // MARK: - SQL Expressions

  static let queued: SQLExpression = Episode.Columns.queueOrder != nil
  static let unqueued: SQLExpression = Episode.Columns.queueOrder == nil
  static let cached: SQLExpression = Episode.Columns.cachedFilename != nil
  static let completed: SQLExpression = Episode.Columns.completionDate != nil
  static let uncompleted: SQLExpression = Episode.Columns.completionDate == nil
  static let unstarted: SQLExpression = Episode.Columns.currentTime == 0
  static let started: SQLExpression = Episode.Columns.currentTime > 0
  static let previouslyQueued: SQLExpression = Episode.Columns.lastQueued != nil

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let podcastId = Column("podcastId")
    static let guid = Column("guid")
    static let media = Column("media")
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
    static let creationDate = Column("creationDate")
  }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(ColumnExpression, SQLExpressible)] {
    [
      (Columns.guid, unsaved.guid),
      (Columns.media, unsaved.media),
      (Columns.title, unsaved.title),
      (Columns.pubDate, unsaved.pubDate),
      (Columns.description, unsaved.description),
      (Columns.link, unsaved.link),
      (Columns.image, unsaved.image),
    ]
  }

  func rssEquals(_ other: Episode) -> Bool {
    unsaved.media == other.unsaved.media && unsaved.title == other.unsaved.title
      && unsaved.pubDate == other.unsaved.pubDate
      && unsaved.description == other.unsaved.description && unsaved.link == other.unsaved.link
      && unsaved.image == other.unsaved.image
  }

  // MARK: - EpisodeDisplayable / EpisodeFilterable

  var title: String { unsaved.title }
  var pubDate: Date { unsaved.pubDate }
  var duration: CMTime {
    get { unsaved.duration }
    set { unsaved.duration = newValue }
  }
  var cached: Bool { unsaved.cached }
  var completed: Bool { unsaved.completed }
  var started: Bool { unsaved.started }
  var queued: Bool { unsaved.queued }
}

// MARK: - DerivableRequest

extension DerivableRequest<Episode> {
  func maxPubDate() -> Self {
    select(max(Episode.Columns.pubDate))
  }

  func queued() -> Self {
    filter(Episode.queued)
  }

  func unqueued() -> Self {
    filter(Episode.unqueued)
  }

  func completed() -> Self {
    filter(Episode.completed)
  }

  func uncompleted() -> Self {
    filter(Episode.uncompleted)
  }

  func started() -> Self {
    filter(Episode.started)
  }

  func unstarted() -> Self {
    filter(Episode.unstarted)
  }
}
