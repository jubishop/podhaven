// Copyright Justin Bishop, 2025 

import Foundation

protocol PodcastSearchResult {
  var searchText: String { get }
  var result: PodcastResultConvertible? { get }
}
