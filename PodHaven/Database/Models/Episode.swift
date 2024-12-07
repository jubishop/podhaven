// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct UnsavedEpisode: Savable {
  let guid: String
  let podcastId: Int64
  var media: URL?
  var title: String?
  var description: String?
  var link: URL?

  init(
    guid: String,
    podcast: Podcast,
    media: URL? = nil,
    title: String? = nil,
    description: String? = nil,
    link: URL? = nil
  ) {
    self.guid = guid
    self.podcastId = podcast.id
    self.media = try? media?.convertToValidURL()
    self.title = title
    self.description = description
    self.link = try? link?.convertToValidURL()
  }
}

typealias Episode = Saved<UnsavedEpisode>

extension Episode {
  static let podcast = belongsTo(Podcast.self)
  var podcast: QueryInterfaceRequest<Podcast> {
    request(for: Self.podcast)
  }
}
