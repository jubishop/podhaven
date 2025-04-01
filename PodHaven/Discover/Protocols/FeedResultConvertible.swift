// Copyright Justin Bishop, 2025

import Foundation

protocol FeedResultConvertible {
  var url: FeedURL { get }
  var image: URL? { get }
  var title: String { get }
  var description: String { get }
  var link: URL? { get }

  func toUnsavedPodcast() throws -> UnsavedPodcast
}

extension FeedResultConvertible {
  func toUnsavedPodcast() throws -> UnsavedPodcast {
    guard let image = image
    else { throw Err.msg("No image for \(title)") }

    return try UnsavedPodcast(
      feedURL: url,
      title: title,
      image: image,
      description: description,
      link: link
    )
  }
}
