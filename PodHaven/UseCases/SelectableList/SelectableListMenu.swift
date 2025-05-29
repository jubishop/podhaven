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
          Button("Select All") {
            list.selectAllEntries()
          }
        }
        if list.anySelected {
          Button("Unselect All") {
            list.unselectAllEntries()
          }
        }
      },
      label: {
        Image(systemName: "checklist")
      }
    )
  }
}

#if DEBUG
#Preview {
  @Previewable @State var list = FakeSelectableList()

  VStack(spacing: 20) {
    SelectableListMenu(list: list)
    Divider()
    Text("Selected: \(list.selected)")
    Button("Select Some") {
      list.selectSomeEntries()
    }
  }
}
#endif
