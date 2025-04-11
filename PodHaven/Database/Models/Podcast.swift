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
  ) throws {
    self.feedURL = FeedURL(try feedURL.rawValue.convertToValidURL())
    self.title = title
    self.image = try image.convertToValidURL()
    self.description = description
    self.link = try? link?.convertToValidURL()
    self.lastUpdate = lastUpdate ?? Date.epoch
    self.subscribed = subscribed ?? false
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
  var episodes: QueryInterfaceRequest<Episode> {
    request(for: Self.episodes)
  }

  static let unfinishedEpisodes = episodes.filter(Schema.completedColumn == false)
  var unfinishedEpisodes: QueryInterfaceRequest<Episode> {
    request(for: Self.unfinishedEpisodes)
  }

  static let unstartedEpisodes = unfinishedEpisodes.filter(Schema.currentTimeColumn == 0)
  var unstartedEpisodes: QueryInterfaceRequest<Episode> {
    request(for: Self.unstartedEpisodes)
  }

  static let unqueuedEpisodes = unstartedEpisodes.filter(Schema.queueOrderColumn == nil)
  var unqueuedEpisodes: QueryInterfaceRequest<Episode> {
    request(for: Self.unqueuedEpisodes)
  }
}
