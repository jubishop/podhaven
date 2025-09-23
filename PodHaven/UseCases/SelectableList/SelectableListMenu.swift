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
          Button(
            action: { list.selectAllEntries() },
            label: { AppLabel.selectAll.label }
          )
          .tint(.blue)
        }
        if list.anySelected {
          Button(
            action: { list.unselectAllEntries() },
            label: { AppLabel.unselectAll.label }
          )
          .tint(.gray)
        }
      },
      label: {
        AppLabel.selectAll.image
      }
    )
  }
}
