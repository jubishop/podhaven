// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import SavedMacro
import Tagged

typealias GUID = Tagged<UnsavedEpisode, String>

typealias MediaURL = Tagged<UnsavedEpisode, URL>

struct UnsavedEpisode: Savable, Stringable {
  static let databaseTableName: String = "episode"

  var podcastId: Podcast.ID?
  let guid: GUID
  var media: MediaURL
  var title: String
  var pubDate: Date
  var duration: CMTime
  var description: String?
  var link: URL?
  var image: URL?
  var completionDate: Date?
  var currentTime: CMTime
  var queueOrder: Int?

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
    queueOrder: Int? = nil
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
  }

  // MARK: - Savable

  var toString: String { "\(media.toString) - \(self.title)" }
  var searchableString: String { self.title }

  // MARK: - State Getters

  var queued: Bool { self.queueOrder != nil }
  var completed: Bool { self.completionDate != nil }
  var started: Bool { self.currentTime.seconds > 0 }
}

@Saved<UnsavedEpisode>
struct Episode: Saved {
  // MARK: - Associations

  static let podcast = belongsTo(Podcast.self)
  var podcastID: Podcast.ID { self.podcastId! }

  // MARK: - SQL Expressions

  static let queued: SQLExpression = Episode.Columns.queueOrder != nil
  static let unqueued: SQLExpression = Episode.Columns.queueOrder == nil
  static let completed: SQLExpression = Episode.Columns.completionDate != nil
  static let uncompleted: SQLExpression = Episode.Columns.completionDate == nil
  static let unstarted: SQLExpression = Episode.Columns.currentTime == 0
  static let started: SQLExpression = Episode.Columns.currentTime > 0

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
  }
}

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
