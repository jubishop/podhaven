// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import Tagged

@testable import PodHaven

enum TestHelpers {
  static func unsavedEpisode(
    guid: String = String.random(),
    podcastId: Podcast.ID? = nil,
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
      podcastId: podcastId,
      guid: guid,
      media: media,
      title: title,
      pubDate: pubDate,
      duration: duration,
      description: description,
      link: link,
      image: image,
      completed: completed,
      currentTime: currentTime,
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
