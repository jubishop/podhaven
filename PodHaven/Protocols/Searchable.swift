// Copyright Justin Bishop, 2025

import Foundation

protocol Searchable: Equatable, Hashable, Identifiable, Sendable {
  var searchableString: String { get }
}
