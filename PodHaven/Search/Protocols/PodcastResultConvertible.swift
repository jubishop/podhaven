// Copyright Justin Bishop, 2025

import Foundation

protocol PodcastResultConvertible: Hashable, Identifiable {
  var convertibleFeeds: [any FeedResultConvertible] { get }
}

extension PodcastResultConvertible {
  var id: [FeedURL] { convertibleFeeds.map(\.url) }

  func hash(into hasher: inout Hasher) {
    hasher.combine(convertibleFeeds.map(\.url))
  }
}
