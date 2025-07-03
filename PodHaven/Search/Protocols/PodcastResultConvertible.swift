// Copyright Justin Bishop, 2025

import Foundation

protocol PodcastResultConvertible {
  var convertibleFeeds: [FeedResultConvertible] { get }
}
