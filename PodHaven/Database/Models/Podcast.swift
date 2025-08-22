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
  Savable,
  Stringable,
  TimestampedRecord
{
  var id: FeedURL { feedURL }

  static let databaseTableName: String = "podcast"

  let feedURL: FeedURL
  let title: String
  let image: URL
  let description: String
  let link: URL?
  var lastUpdate: Date
  var subscriptionDate: Date?
  let cacheAllEpisodes: Bool
  var creationDate: Date?

  init(
    feedURL: FeedURL,
    title: String,
    image: URL,
    description: String,
    link: URL? = nil,
    lastUpdate: Date? = nil,
    subscriptionDate: Date? = nil,
    cacheAllEpisodes: Bool = false,
    creationDate: Date? = nil,
  ) throws(ModelError) {
    do {
      self.feedURL = FeedURL(try feedURL.rawValue.convertToValidURL())
      self.title = title
      self.image = try image.convertToValidURL()
      self.description = description
      self.link = try? link?.convertToValidURL()
      self.lastUpdate = lastUpdate ?? Date.epoch
      self.subscriptionDate = subscriptionDate
      self.cacheAllEpisodes = cacheAllEpisodes
      self.creationDate = creationDate
    } catch {
      throw ModelError.podcastInitializationFailure(feedURL: feedURL, title: title, caught: error)
    }
  }

  // MARK: - Savable

  var toString: String { "(\(feedURL.toString)) - \(self.title)" }
  var searchableString: String { self.title }

  // MARK: - State Getters

  var subscribed: Bool { self.subscriptionDate != nil }
}

@Saved<UnsavedPodcast>
struct Podcast: PodcastDisplayable, Saved, RSSUpdatable {
  // MARK: - Associations

  static let episodes = hasMany(Episode.self).order(\.pubDate.desc)
  static let episodesSubquery = hasManySubquery(Episode.self)

  // MARK: - SQL Expressions

  static let subscribed: SQLExpression = Columns.subscriptionDate != nil
  static let unsubscribed: SQLExpression = Columns.subscriptionDate == nil

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let feedURL = Column("feedURL")
    static let title = Column("title")
    static let image = Column("image")
    static let description = Column("description")
    static let link = Column("link")
    static let lastUpdate = Column("lastUpdate")
    static let subscriptionDate = Column("subscriptionDate")
    static let cacheAllEpisodes = Column("cacheAllEpisodes")
    static let creationDate = Column("creationDate")
  }

  // MARK: - RSSUpdatable

  var rssUpdatableColumns: [(ColumnExpression, SQLExpressible)] {
    [
      (Columns.feedURL, unsaved.feedURL),
      (Columns.title, unsaved.title),
      (Columns.image, unsaved.image),
      (Columns.description, unsaved.description),
      (Columns.link, unsaved.link),
      (Columns.lastUpdate, unsaved.lastUpdate),
    ]
  }

  // MARK: - RSS Equality

  func rssEquals(_ other: Podcast) -> Bool {
    unsaved.feedURL == other.unsaved.feedURL && unsaved.title == other.unsaved.title
      && unsaved.image == other.unsaved.image && unsaved.description == other.unsaved.description
      && unsaved.link == other.unsaved.link && unsaved.lastUpdate == other.unsaved.lastUpdate
  }

  // MARK: - PodcastDisplayable

  var image: URL { unsaved.image }
  var title: String { unsaved.title }
  var description: String { unsaved.description }
  var link: URL? { unsaved.link }
  var subscribed: Bool { unsaved.subscribed }
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
