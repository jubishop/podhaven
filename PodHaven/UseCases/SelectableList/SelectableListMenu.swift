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
          AppLabel.selectAll.labelButton {
            list.selectAllEntries()
          }
        }
        if list.anySelected {
          AppLabel.unselectAll.labelButton {
            list.unselectAllEntries()
          }
        }
      },
      label: {
        AppLabel.selectAll.image
      }
    )
  }
}
