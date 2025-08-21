// Copyright Justin Bishop, 2025

import Foundation

/// Protocol for ViewModels that support sorting with a SortMethod enum
@MainActor protocol Sortable {
  /// The SortMethod enum type that defines available sort options
  associatedtype SortMethod: CaseIterable & RawRepresentable where SortMethod.RawValue == String, SortMethod.AllCases: RandomAccessCollection
  
  /// The current sort method being used
  var currentSortMethod: SortMethod? { get set }
  
  /// Performs sorting using the specified method
  func sort(by method: SortMethod)
}
