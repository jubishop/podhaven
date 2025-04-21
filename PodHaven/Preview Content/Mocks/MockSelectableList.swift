// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor
final class MockSelectableList: SelectableList {
  enum Selected: String {
    case all
    case none
    case some
  }
  var selected: Selected = .some

  var isSelecting: Bool = false
  var anyNotSelected: Bool = true
  var anySelected: Bool = true

  func selectAllEntries() {
    selected = .all
    anyNotSelected = false
    anySelected = true
  }

  func unselectAllEntries() {
    selected = .none
    anyNotSelected = true
    anySelected = false
  }

  func selectSomeEntries() {
    selected = .some
    anyNotSelected = true
    anySelected = true
  }
}
