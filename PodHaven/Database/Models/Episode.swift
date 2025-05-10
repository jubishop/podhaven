// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

typealias GUID = Tagged<UnsavedEpisode, String>
typealias MediaURL = Tagged<UnsavedEpisode, URL>

struct UnsavedEpisode: Savable, Stringable {
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

  // MARK: - Stringable

  var toString: String { self.title }
}

typealias Episode = Saved<UnsavedEpisode>

extension Episode {
  static let podcast = belongsTo(Podcast.self)
}

extension DerivableRequest<Episode> {
  func maxPubDate() -> Self {
    select(max(Schema.pubDateColumn))
  }

  func inQueue() -> Self {
    filter(Schema.queueOrderColumn != nil)
  }

  func unqueued() -> Self {
    filter(Schema.queueOrderColumn == nil)
  }

  func completed() -> Self {
    filter(Schema.completedColumn == true)
  }

  func uncompleted() -> Self {
    filter(Schema.completedColumn == false)
  }

  func unstarted() -> Self {
    filter(Schema.currentTimeColumn == 0)
  }
}
