// Copyright Justin Bishop, 2025

import Foundation

protocol Searchable: Equatable, Hashable, Sendable {
  var searchableString: String { get }
}
