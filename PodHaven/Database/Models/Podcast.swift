// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections
import SavedMacro
import Tagged

typealias FeedURL = Tagged<UnsavedPodcast, URL>

struct UnsavedPodcast: Savable, Stringable {
  static let databaseTableName: String = "podcast"

  var feedURL: FeedURL
  var title: String
  var image: URL
  var description: String
  var link: URL?
  var lastUpdate: Date
  var subscribed: Bool

  init(
    feedURL: FeedURL,
    title: String,
    image: URL,
    description: String,
    link: URL? = nil,
    lastUpdate: Date? = nil,
    subscribed: Bool? = nil
  ) throws(ModelError) {
    do {
      self.feedURL = FeedURL(try feedURL.rawValue.convertToValidURL())
      self.title = title
      self.image = try image.convertToValidURL()
      self.description = description
      self.link = try? link?.convertToValidURL()
      self.lastUpdate = lastUpdate ?? Date.epoch
      self.subscribed = subscribed ?? false
    } catch {
      throw ModelError.podcastInitializationFailure(feedURL: feedURL, title: title, caught: error)
    }
  }

  // MARK: - Savable

  var toString: String { "(\(feedURL.toString)) - \(self.title)" }
  var searchableString: String { self.title }
}

@Saved<UnsavedPodcast>
struct Podcast: Saved, RSSUpdatable {
  // MARK: - Associations

  static let episodes = hasMany(Episode.self).order(\.pubDate.desc)
  static let episodesSubquery = hasManySubquery(Episode.self)

  // MARK: - SQL Expressions

  static let subscribed: SQLExpression = Columns.subscribed == true
  static let unsubscribed: SQLExpression = Columns.subscribed == false

  // MARK: - Columns

  enum Columns {
    static let id = Column("id")
    static let feedURL = Column("feedURL")
    static let title = Column("title")
    static let image = Column("image")
    static let description = Column("description")
    static let link = Column("link")
    static let lastUpdate = Column("lastUpdate")
    static let subscribed = Column("subscribed")
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
}

extension DerivableRequest<Podcast> {
  func subscribed() -> Self {
    filter(Podcast.subscribed)
  }

  func unsubscribed() -> Self {
    filter(Podcast.unsubscribed)
  }
}
