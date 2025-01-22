// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import Tagged
import IdentifiedCollections

typealias EpisodeArray = IdentifiedArray<String, Episode>  // guid

struct UnsavedEpisode: Savable {
  let guid: String
  var podcastId: Podcast.ID?
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
    podcastId: Podcast.ID? = nil,
    guid: String,
    media: URL,
    title: String,
    pubDate: Date? = nil,
    duration: CMTime? = nil,
    description: String? = nil,
    link: URL? = nil,
    image: URL? = nil,
    completed: Bool? = nil,
    currentTime: CMTime? = nil,
    queueOrder: Int? = nil
  ) throws {
    self.podcastId = podcastId
    self.guid = guid
    self.media = try media.convertToValidURL()
    self.title = title
    self.pubDate = pubDate ?? Date()
    self.duration = duration ?? CMTime.zero
    self.description = description
    self.link = try? link?.convertToValidURL()
    self.image = try? image?.convertToValidURL()
    self.completed = completed ?? false
    self.currentTime = currentTime ?? CMTime.zero
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
