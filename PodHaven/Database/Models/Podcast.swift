// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections
import Tagged

typealias FeedURL = Tagged<UnsavedPodcast, URL>

struct UnsavedPodcast: Savable, Stringable {
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

  var toString: String { self.title }

  // MARK: - Helpers

  var formattedLastUpdate: String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "MM/dd/yyyy"
    return dateFormatter.string(from: lastUpdate)
  }
}

typealias Podcast = Saved<UnsavedPodcast>

extension Podcast {
  static let episodes = hasMany(Episode.self).order(Schema.pubDateColumn.desc)

  // MARK: - Annotation Queries

  static let episodesSubquery = hasManySubquery(Episode.self)
  static let unfinishedEpisodes = episodesSubquery.uncompleted()
  static let unstartedEpisodes = unfinishedEpisodes.unstarted()
  static let unqueuedEpisodes = unstartedEpisodes.unqueued()

  // MARK: - SQL Expressions

  static let subscribed: SQLExpression = Schema.subscribedColumn == true
  static let unsubscribed: SQLExpression = Schema.subscribedColumn == false
}

extension DerivableRequest<Podcast> {
  func subscribed() -> Self {
    filter(Podcast.subscribed)
  }

  func unsubscribed() -> Self {
    filter(Podcast.unsubscribed)
  }
}
