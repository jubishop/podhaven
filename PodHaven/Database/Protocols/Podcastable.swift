// Copyright Justin Bishop, 2025 

import Foundation

protocol Podcastable: Hashable {
  var image: URL { get }
  var title: String { get }
}
