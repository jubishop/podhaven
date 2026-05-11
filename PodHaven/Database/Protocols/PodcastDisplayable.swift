// Copyright Justin Bishop, 2025

import Foundation

protocol PodcastDisplayable: PodcastListable {
  var description: String { get }
  var link: URL? { get }
}
