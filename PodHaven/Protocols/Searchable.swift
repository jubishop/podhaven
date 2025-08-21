// Copyright Justin Bishop, 2025

import Foundation

protocol Searchable: Equatable, Hashable, Identifiable {
  var searchableString: String { get }
}
