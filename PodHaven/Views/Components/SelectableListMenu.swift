// Copyright Justin Bishop, 2025

import SwiftUI

@MainActor struct SelectableListMenu<List: SelectableList>: View {
  private let list: List

  init(list: List) {
    self.list = list
  }

  var body: some View {
    if list.isSelecting {
      Menu(
        content: {
          AppIcon.editFinished.labelButton {
            list.setSelecting(false)
          }
          if list.anyNotSelected {
            AppIcon.selectAll.labelButton {
              list.selectAllEntries()
            }
          }
          if list.anySelected {
            AppIcon.unselectAll.labelButton {
              list.unselectAllEntries()
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
