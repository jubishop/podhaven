// Copyright Justin Bishop, 2025

import SwiftUI

@MainActor struct SelectableListMenu<List: SelectableList>: View {
  private let list: List
  private let hasUnselectedEntries: @MainActor () -> Bool
  private let hasSelectedEntries: @MainActor () -> Bool
  private let selectAll: @MainActor () -> Void
  private let unselectAll: @MainActor () -> Void

  init(list: List) {
    self.init(
      list: list,
      hasUnselectedEntries: { list.anyNotSelected },
      hasSelectedEntries: { list.anySelected },
      selectAll: { list.selectAllEntries() },
      unselectAll: { list.unselectAllEntries() }
    )
  }

  init(
    list: List,
    hasUnselectedEntries: @escaping @MainActor () -> Bool,
    hasSelectedEntries: @escaping @MainActor () -> Bool,
    selectAll: @escaping @MainActor () -> Void,
    unselectAll: @escaping @MainActor () -> Void
  ) {
    self.list = list
    self.hasUnselectedEntries = hasUnselectedEntries
    self.hasSelectedEntries = hasSelectedEntries
    self.selectAll = selectAll
    self.unselectAll = unselectAll
  }

  var body: some View {
    if list.isSelecting {
      Menu(
        content: {
          AppIcon.editFinished.labelButton {
            list.setSelecting(false)
          }
          if hasUnselectedEntries() {
            AppIcon.selectAll.labelButton {
              selectAll()
            }
          }
          if hasSelectedEntries() {
            AppIcon.unselectAll.labelButton {
              unselectAll()
            }
          }
        },
        label: {
          AppIcon.editFinished.image
        }
      )
    } else {
      AppIcon.editItems.labelButton {
        list.setSelecting(true)
      }
    }
  }
}
