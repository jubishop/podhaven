// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections
import SavedMacro
import Tagged

typealias FeedURL = Tagged<UnsavedPodcast, URL>

struct UnsavedPodcast:
  Identifiable,
  PodcastDisplayable,
  RSSUpdatable,
  Savable,
  Stringable
{
  var id: FeedURL { feedURL }

  static let databaseTableName: String = "podcast"

  // Feed
  let feedURL: FeedURL
  let title: String
  let image: URL
  let description: String
  let link: URL?

  // User
  let lastUpdate: Date
  let subscriptionDate: Date?
  let defaultPlaybackRate: Double?
  let queueAllEpisodes: QueueAllEpisodes
  let cacheAllEpisodes: CacheAllEpisodes
  let notifyNewEpisodes: Bool

  init(
    feedURL: FeedURL,
    title: String,
    image: URL,
    description: String,
    link: URL?,
    lastUpdate: Date? = nil,
    subscriptionDate: Date? = nil,
    defaultPlaybackRate: Double? = nil,
    queueAllEpisodes: QueueAllEpisodes = .never,
    cacheAllEpisodes: CacheAllEpisodes = .never,
    notifyNewEpisodes: Bool = false
  ) throws(ModelError) {
    do {
      self.feedURL = try feedURL.convertToHTTPSURL()
      self.title = title
      self.image = try image.convertToHTTPSURL()
      self.description = description
      self.link = try? link?.convertToHTTPSURL()
      self.lastUpdate = lastUpdate ?? Date.epoch
      self.subscriptionDate = subscriptionDate
      self.defaultPlaybackRate = defaultPlaybackRate
      self.queueAllEpisodes = queueAllEpisodes
      self.cacheAllEpisodes = cacheAllEpisodes
      self.notifyNewEpisodes = notifyNewEpisodes
    } catch {
      throw ModelError.podcastInitializationFailure(feedURL: feedURL, title: title, caught: error)
    }
  }

  // MARK: - Savable

  var toString: String { "(\(feedURL.toString)) - \(title)" }
  var searchableString: String { "\(title) - \(description)" }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(any ColumnExpression, any SQLExpressible)] {
    [
      (Podcast.Columns.feedURL, feedURL),
      (Podcast.Columns.title, title),
      (Podcast.Columns.image, image),
      (Podcast.Columns.description, description),
      (Podcast.Columns.link, link),
    ]
  }

  func rssEquals(_ other: UnsavedPodcast) -> Bool {
    feedURL == other.feedURL
      && title == other.title
      && image == other.image
      && description == other.description
      && link == other.link
  }

  // MARK: - Reset

  func toOriginalUnsavedPodcast() throws -> UnsavedPodcast {
    try UnsavedPodcast(
      feedURL: feedURL,
      title: title,
      image: image,
      description: description,
      link: link
    )
  }
}

@Saved<UnsavedPodcast>
struct Podcast: PodcastDisplayable, Saved, RSSUpdatable {
  // MARK: - Associations

  static let episodes = hasMany(Episode.self).order(\.pubDate.desc)

  // MARK: - SQL Expressions

  static let subscribed: SQLExpression = Columns.subscriptionDate != nil
  static let unsubscribed: SQLExpression = Columns.subscriptionDate == nil
  static func contains(_ pattern: String) -> SQLExpression {
    Columns.title.lowercased.like(pattern) || Columns.description.lowercased.like(pattern)
  }

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let creationDate = Column("creationDate")
    static let feedURL = Column("feedURL")
    static let title = Column("title")
    static let image = Column("image")
    static let description = Column("description")
    static let link = Column("link")
    static let lastUpdate = Column("lastUpdate")
    static let subscriptionDate = Column("subscriptionDate")
    static let defaultPlaybackRate = Column("defaultPlaybackRate")
    static let queueAllEpisodes = Column("queueAllEpisodes")
    static let cacheAllEpisodes = Column("cacheAllEpisodes")
    static let notifyNewEpisodes = Column("notifyNewEpisodes")
  }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(any ColumnExpression, any SQLExpressible)] {
    unsaved.rssUpdatableColumns
  }

  func rssEquals(_ other: Podcast) -> Bool {
    unsaved.rssEquals(other.unsaved)
  }

  // MARK: - PodcastDisplayable

  var feedURL: FeedURL { unsaved.feedURL }
  var image: URL { unsaved.image }
  var title: String { unsaved.title }
  var description: String { unsaved.description }
  var link: URL? { unsaved.link }
  var subscriptionDate: Date? { unsaved.subscriptionDate }
  var defaultPlaybackRate: Double? { unsaved.defaultPlaybackRate }
  var queueAllEpisodes: QueueAllEpisodes { unsaved.queueAllEpisodes }
  var cacheAllEpisodes: CacheAllEpisodes { unsaved.cacheAllEpisodes }
  var notifyNewEpisodes: Bool { unsaved.notifyNewEpisodes }

  // MARK: - Reset

  func toOriginalUnsavedPodcast() throws -> UnsavedPodcast {
    try unsaved.toOriginalUnsavedPodcast()
  }
}

// MARK: - DerivableRequest

extension DerivableRequest<Podcast> {
  func subscribed() -> Self {
    filter(Podcast.subscribed)
  }

  func unsubscribed() -> Self {
    filter(Podcast.unsubscribed)
  }
}
