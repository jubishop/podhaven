// Copyright Justin Bishop, 2025

import Foundation

protocol PodcastResultConvertible: Hashable {
  var convertibleFeeds: [FeedResultConvertible] { get }
}
