// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor class SelectableListItemModel<Item> {
  let isSelected: Binding<Bool>
  let item: Item
  let isSelecting: Bool

  init(isSelected: Binding<Bool>, item: Item, isSelecting: Bool) {
    self.isSelected = isSelected
    self.item = item
    self.isSelecting = isSelecting
  }
}
