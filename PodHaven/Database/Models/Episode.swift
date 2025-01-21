// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import Tagged

struct UnsavedEpisode: Savable {
  let guid: String
  var podcastId: Tagged<Podcast, Int64>?
  var title: String
  var media: URL
  var currentTime: CMTime
  var completed: Bool
  var duration: CMTime
  var pubDate: Date
  var description: String?
  var link: URL?
  var image: URL?
  var queueOrder: Int?

  init(
    guid: String,
    podcastId: Tagged<Podcast, Int64>? = nil,
    title: String,
    media: URL,
    currentTime: CMTime? = nil,
    completed: Bool? = nil,
    duration: CMTime? = nil,
    pubDate: Date? = nil,
    description: String? = nil,
    link: URL? = nil,
    image: URL? = nil,
    queueOrder: Int? = nil
  ) throws {
    self.guid = guid
    self.podcastId = podcastId
    self.title = title
    self.media = try media.convertToValidURL()
    self.currentTime = currentTime ?? CMTime.zero
    self.completed = completed ?? false
    self.duration = duration ?? CMTime.zero
    self.pubDate = pubDate ?? Date()
    self.description = description
    self.link = try? link?.convertToValidURL()
    self.image = try? image?.convertToValidURL()
    self.queueOrder = queueOrder
  }

  // MARK: - Savable

  var toString: String { self.title }
}

typealias Episode = Saved<UnsavedEpisode>

extension Episode {
  static let podcast = belongsTo(Podcast.self)
  var podcast: QueryInterfaceRequest<Podcast> {
    request(for: Self.podcast)
  }
}
