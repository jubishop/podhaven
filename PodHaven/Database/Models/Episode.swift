// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation
import GRDB

struct UnsavedEpisode: Savable {
  let guid: String
  var podcastId: Int64?
  var media: URL
  var currentTime: CMTime
  var duration: CMTime
  var pubDate: Date
  var title: String?
  var description: String?
  var link: URL?
  var image: URL?
  var queueOrder: Int?

  init(
    guid: String,
    podcastId: Int64? = nil,
    media: URL,
    currentTime: CMTime? = nil,
    duration: CMTime? = nil,
    pubDate: Date? = nil,
    title: String? = nil,
    description: String? = nil,
    link: URL? = nil,
    image: URL? = nil,
    queueOrder: Int? = nil
  ) throws {
    self.guid = guid
    self.podcastId = podcastId
    self.media = try media.convertToValidURL()
    self.currentTime = currentTime ?? CMTime.zero
    self.duration = duration ?? CMTime.zero
    self.pubDate = pubDate ?? Date()
    self.title = title
    self.description = description
    self.link = try? link?.convertToValidURL()
    self.image = try? image?.convertToValidURL()
    self.queueOrder = queueOrder
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
