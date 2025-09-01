// Copyright Justin Bishop, 2025

import Foundation

protocol PodcastDisplayable: Gridable, Hashable, Sendable, Stringable {
  var feedURL: FeedURL { get }
  var image: URL { get }
  var title: String { get }
  var description: String { get }
  var link: URL? { get }
  var subscribed: Bool { get }
}
