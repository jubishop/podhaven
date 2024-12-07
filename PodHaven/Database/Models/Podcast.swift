// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct UnsavedPodcast: Savable {
  var feedURL: URL
  var title: String
  var link: URL?
  var image: URL?
  var description: String?

  init(
    feedURL: URL,
    title: String,
    link: URL? = nil,
    image: URL? = nil,
    description: String? = nil
  ) throws {
    self.feedURL = try feedURL.convertToValidURL()
    self.title = title
    self.link = try link?.convertToValidURL()
    self.image = try? image?.convertToValidURL()
    self.description = description
  }
}

typealias Podcast = Saved<UnsavedPodcast>

extension Podcast {
  static let episodes = hasMany(Episode.self)
  var episodes: QueryInterfaceRequest<Episode> {
    request(for: Self.episodes)
  }
}
