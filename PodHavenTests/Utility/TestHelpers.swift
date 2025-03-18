// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import Tagged

@testable import PodHaven

enum TestHelpers {
  static func unsavedEpisode(
    podcastId: Podcast.ID? = nil,
    guid: GUID = GUID(String.random()),
    media: MediaURL = MediaURL(URL.valid()),
    title: String = String.random(),
    pubDate: Date? = Date(),
    duration: CMTime? = nil,
    description: String? = nil,
    link: URL? = nil,
    image: URL? = nil,
    completed: Bool? = nil,
    currentTime: CMTime? = nil,
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
    feedURL: FeedURL = FeedURL(URL.valid()),
    title: String = String.random(),
    image: URL = URL.valid(),
    description: String = String.random(),
    link: URL? = nil,
    lastUpdate: Date = Date(),
    subscribed: Bool = true
  ) throws -> UnsavedPodcast {
    try UnsavedPodcast(
      feedURL: feedURL,
      title: title,
      image: image,
      description: description,
      link: link,
      lastUpdate: lastUpdate,
      subscribed: subscribed
    )
  }
}
