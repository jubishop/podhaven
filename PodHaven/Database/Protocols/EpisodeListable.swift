// Copyright Justin Bishop, 2026

import Foundation

protocol EpisodeListable: EpisodeFoundational, Hashable {
  var feedURL: FeedURL { get }
  var image: URL { get }
  var podcastImage: URL { get }
}
