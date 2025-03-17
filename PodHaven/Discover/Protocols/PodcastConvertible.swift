// Copyright Justin Bishop, 2025

import Foundation

// TODO: Can we use this in PodcastFeed?
protocol PodcastConvertible {
  var url: FeedURL { get }
  var image: URL? { get }
  var title: String { get }
  var description: String { get }

  func toUnsavedPodcast() throws -> UnsavedPodcast
}

extension PodcastConvertible {
  func toUnsavedPodcast() throws -> UnsavedPodcast {
    guard let image = image
    else { throw Err.msg("No image for \(title)") }

    return try UnsavedPodcast(
      feedURL: url,
      title: title,
      image: image,
      description: description,
      lastUpdate: Date.epoch,
      subscribed: false
    )
  }
}
