// Copyright Justin Bishop, 2025

import Foundation

/// For navigation classes that manage a navigation path and can be reset.
/// This ensures consistent behavior across all tab navigation systems.
@MainActor
protocol ManagingNavigationPaths: AnyObject, Observable {
  associatedtype Destination: Hashable

  /// The navigation path for this tab
  var path: [Destination] { get set }

  /// Unique identifier that changes when the navigation should be completely reset
  var resetId: UUID { get set }

  /// Clears the navigation path and generates a new reset ID to force NavigationStack reset
  func clearPath()
}

extension ManagingNavigationPaths {
  func clearPath() {
    path.removeAll()
    resetId = UUID()
  }
}
