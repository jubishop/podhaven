// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor final class SelectableListItemModel<Item: Stringable> {
  let isSelected: Binding<Bool>
  let item: Item
  let isSelecting: Bool

  init(isSelected: Binding<Bool>, item: Item, isSelecting: Bool) {
    self.isSelected = isSelected
    self.item = item
    self.isSelecting = isSelecting
  }
}
