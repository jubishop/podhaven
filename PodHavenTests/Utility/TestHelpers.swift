// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@testable import PodHaven

enum TestHelpers {
  static func unsavedEpisode(
    guid: String = String.random(),
    podcastId: Int64? = nil,
    title: String = String.random(),
    media: URL = URL.valid(),
    currentTime: CMTime? = nil,
    completed: Bool? = nil,
    duration: CMTime? = nil,
    pubDate: Date? = Date(),
    description: String? = nil,
    link: URL? = nil,
    image: URL? = nil,
    queueOrder: Int? = nil
  ) throws -> UnsavedEpisode {
    try UnsavedEpisode(
      guid: guid,
      podcastId: podcastId,
      title: title,
      media: media,
      currentTime: currentTime,
      completed: completed,
      duration: duration,
      pubDate: pubDate,
      description: description,
      link: link,
      image: image,
      queueOrder: queueOrder
    )
  }

  static func unsavedPodcast(
    feedURL: URL = URL.valid(),
    title: String = String.random(),
    image: URL = URL.valid(),
    description: String = String.random(),
    link: URL? = nil,
    lastUpdate: Date? = nil
  ) throws -> UnsavedPodcast {
    try UnsavedPodcast(
      feedURL: feedURL,
      title: title,
      image: image,
      description: description,
      link: link,
      lastUpdate: lastUpdate
    )
  }
}
