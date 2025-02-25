// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

typealias GUID = Tagged<UnsavedEpisode, String>
typealias MediaURL = Tagged<UnsavedEpisode, URL>
typealias EpisodeArray = IdentifiedArray<GUID, Episode>

struct UnsavedEpisode: Savable {
  var podcastId: Podcast.ID?
  let guid: GUID
  var media: MediaURL
  var title: String
  var pubDate: Date
  var duration: CMTime
  var description: String?
  var link: URL?
  var image: URL?
  var completed: Bool
  var currentTime: CMTime
  var queueOrder: Int?

  init(
    podcastId: Podcast.ID? = nil,
    guid: GUID,
    media: MediaURL,
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
    self.media = MediaURL(try media.rawValue.convertToValidURL())
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

extension Episode: EpisodeIdentifiable {
  var title: String { value.title }
}
