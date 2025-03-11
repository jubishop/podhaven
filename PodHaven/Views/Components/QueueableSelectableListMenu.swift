// Copyright Justin Bishop, 2025

import SwiftUI

struct QueueableSelectableListMenu: View {
  private let list: QueueableSelectableList

  init(list: QueueableSelectableList) {
    self.list = list
  }

  var body: some View {
    Menu(
      content: {
        Button("Add To Top Of Queue") {
          list.addSelectedEpisodesToTopOfQueue()
        }
        Button("Add To Bottom Of Queue") {
          list.addSelectedEpisodesToBottomOfQueue()
        }
        Button("Replace Queue") {
          list.replaceQueue()
        }
        Button("Replace Queue and Play") {
          list.replaceQueueAndPlay()
        }
      },
      label: {
        Image(systemName: "text.badge.plus")
      }
    )
  }
}
