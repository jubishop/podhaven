// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct UnsavedPodcast: Savable {
  var feedURL: URL
  var title: String
  var link: URL?
  var image: URL?
  var podcastDescription: String?

  init(
    feedURL: URL,
    title: String,
    link: URL? = nil,
    image: URL? = nil,
    podcastDescription: String? = nil
  ) throws {
    self.feedURL = try feedURL.convertToValidURL()
    self.title = title
    self.link = try? link?.convertToValidURL()
    self.image = try? image?.convertToValidURL()
    self.podcastDescription = podcastDescription
  }

  // MARK: - CustomStringConvertible

  public var description: String { self.title }
}

typealias Podcast = Saved<UnsavedPodcast>

extension Podcast {
  static let episodes = hasMany(Episode.self).order(Column("pubDate"))
  var episodes: QueryInterfaceRequest<Episode> {
    request(for: Self.episodes)
  }
}
