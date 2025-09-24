// Copyright Justin Bishop, 2025

import SwiftUI

struct SelectableListMenu: View {
  private let list: SelectableList

  init(list: SelectableList) {
    self.list = list
  }

  var body: some View {
    Menu(
      content: {
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
      label: { AppIcon.selectAll.image }
    )
  }
}
