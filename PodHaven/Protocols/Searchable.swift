// Copyright Justin Bishop, 2025

import Foundation

protocol Searchable: Hashable, Identifiable {
  var searchableString: String { get }
}
