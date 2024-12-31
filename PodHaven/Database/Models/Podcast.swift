// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct UnsavedPodcast: Savable {
  var feedURL: URL
  var title: String
  var link: URL?
  var image: URL?
  var description: String?
  var lastUpdate: Date

  init(
    feedURL: URL,
    title: String,
    link: URL? = nil,
    image: URL? = nil,
    description: String? = nil,
    lastUpdate: Date? = nil
  ) throws {
    self.feedURL = try feedURL.convertToValidURL()
    self.title = title
    self.link = try? link?.convertToValidURL()
    self.image = try? image?.convertToValidURL()
    self.description = description
    self.lastUpdate = lastUpdate ?? Date()
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
  static let episodes = hasMany(Episode.self).order(AppDB.pubDateColumn.desc)
  var episodes: QueryInterfaceRequest<Episode> {
    request(for: Self.episodes)
  }
}
