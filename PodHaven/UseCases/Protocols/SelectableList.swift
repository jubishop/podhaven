// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol SelectableList {
  var isSelecting: Bool { get set }
  var anyNotSelected: Bool { get }
  var anySelected: Bool { get }

  func selectAllEntries()
  func unselectAllEntries()
}
