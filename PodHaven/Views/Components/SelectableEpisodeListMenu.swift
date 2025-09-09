// Copyright Justin Bishop, 2025

import SwiftUI

struct SelectableEpisodeListMenu: View {
  private let listModel: any SelectableEpisodeListModel

  init(listModel: any SelectableEpisodeListModel) {
    self.listModel = listModel
  }

  var body: some View {
    Menu(
      content: {
        Button("Add To Top Of Queue") {
          listModel.addSelectedEpisodesToTopOfQueue()
        }
        Button("Add To Bottom Of Queue") {
          listModel.addSelectedEpisodesToBottomOfQueue()
        }
        Button("Replace Queue") {
          listModel.replaceQueueWithSelected()
        }
        Button("Replace Queue and Play") {
          listModel.replaceQueueWithSelectedAndPlay()
        }
        if listModel.selectedEpisodes.contains(where: { !$0.cached }) {
          Button("Cache Selected") {
            listModel.cacheSelectedEpisodes()
          }
        }
      },
      label: {
        AppLabel.queueActions.image
      }
    )
  }
}

#if DEBUG
#Preview {
  SelectableEpisodeListMenu(listModel: StubSelectableEpisodeListModel())
}
#endif
