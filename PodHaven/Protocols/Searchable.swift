// Copyright Justin Bishop, 2025

import Foundation

protocol Searchable: Equatable, Hashable {
  var searchableString: String { get }
}
