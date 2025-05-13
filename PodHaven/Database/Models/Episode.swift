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

  // MARK: - SQL Expressions

  static let queued: SQLExpression = Schema.queueOrderColumn != nil
  static let completed: SQLExpression = Schema.completedColumn == true
  static let uncompleted: SQLExpression = Schema.completedColumn == false
  static let started: SQLExpression = Schema.currentTimeColumn > 0
}

extension DerivableRequest<Episode> {
  func maxPubDate() -> Self {
    select(max(Schema.pubDateColumn))
  }

  func queued() -> Self {
    filter(Episode.queued)
  }

  func unqueued() -> Self {
    filter(Schema.queueOrderColumn == nil)
  }

  func completed() -> Self {
    filter(Episode.completed)
  }

  func uncompleted() -> Self {
    filter(Episode.uncompleted)
  }

  func unstarted() -> Self {
    filter(Schema.currentTimeColumn == 0)
  }
}
