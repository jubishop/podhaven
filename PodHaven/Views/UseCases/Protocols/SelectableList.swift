// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol SelectableList {
  var anyNotSelected: Bool { get }
  var anySelected: Bool { get }

  func selectAllEntries()
  func unselectAllEntries()
}
