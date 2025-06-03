// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import Tagged

@testable import PodHaven

enum TestHelpers {
  @discardableResult
  static func waitForValue<T: Sendable>(
    maxAttempts: Int = 10,
    delay: UInt64 = 10_000_000,  // 10 ms
    _ block: @Sendable @escaping () throws -> T?
  ) async throws -> T {
    var attempts = 0
    while attempts < maxAttempts {
      if let value = try block() {
        return value
      }
      try await Task.sleep(nanoseconds: delay)
      attempts += 1
    }
    throw TestError.waitForValueFailure(String(describing: T.self))
  }

  @discardableResult
  static func waitForValue<T: Sendable>(
    maxAttempts: Int = 10,
    delay: UInt64 = 10_000_000,  // 10 ms
    _ block: @Sendable @escaping () async throws -> T?
  ) async throws -> T {
    var attempts = 0
    while attempts < maxAttempts {
      if let value = try await block() {
        return value
      }
      try await Task.sleep(nanoseconds: delay)
      attempts += 1
    }
    throw TestError.waitForValueFailure(String(describing: T.self))
  }

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
    completionDate: Date? = nil,
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
      completionDate: completionDate,
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
    lastUpdate: Date? = nil,
    subscribed: Bool? = nil
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
