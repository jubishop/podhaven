// Copyright Justin Bishop, 2026

import Foundation

protocol EpisodeListable: EpisodeFoundational, Hashable {
  var image: URL { get }
  var podcastImage: URL { get }
}
