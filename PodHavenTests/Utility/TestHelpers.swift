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
    currentTime: CMTime = CMTime.zero,
    completed: Bool = false,
    duration: CMTime = CMTime.zero,
    pubDate: Date? = Date(),
    description: String = String.random(),
    link: URL = URL.valid(),
    image: URL = URL.valid(),
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
    link: URL = URL.valid(),
    image: URL = URL.valid(),
    description: String = String.random(),
    lastUpdate: Date? = Date()
  ) throws -> UnsavedPodcast {
    try UnsavedPodcast(
      feedURL: feedURL,
      title: title,
      link: link,
      image: image,
      description: description,
      lastUpdate: lastUpdate
    )
  }
}
