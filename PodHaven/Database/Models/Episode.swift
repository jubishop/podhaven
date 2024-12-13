// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct UnsavedEpisode: Savable {
  let guid: String
  var podcastId: Int64?
  var media: URL?
  var pubDate: Date
  var title: String?
  var description: String?
  var link: URL?
  var image: URL?

  init(
    guid: String,
    podcast: Podcast? = nil,
    media: URL? = nil,
    pubDate: Date? = nil,
    title: String? = nil,
    description: String? = nil,
    link: URL? = nil,
    image: URL? = nil
  ) {
    self.guid = guid
    self.podcastId = podcast?.id
    self.media = try? media?.convertToValidURL()
    self.pubDate = pubDate ?? Date()
    self.title = title
    self.description = description
    self.link = try? link?.convertToValidURL()
    self.image = try? image?.convertToValidURL()
  }

  // MARK: - Savable

  var toString: String { self.title ?? self.guid }
}

typealias Episode = Saved<UnsavedEpisode>

extension Episode {
  static let podcast = belongsTo(Podcast.self)
  var podcast: QueryInterfaceRequest<Podcast> {
    request(for: Self.podcast)
  }
}
