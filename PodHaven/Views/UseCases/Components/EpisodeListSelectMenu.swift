// Copyright Justin Bishop, 2025

import SwiftUI

struct EpisodeListSelectMenu: View {
  private let episodeList: EpisodeListSelectable

  init(episodeList: EpisodeListSelectable) {
    self.episodeList = episodeList
  }

  var body: some View {
    Menu(
      content: {
        if episodeList.anyNotSelected {
          Button("Select All") {
            episodeList.selectAllEpisodes()
          }
        }
        if episodeList.anySelected {
          Button("Unselect All") {
            episodeList.unselectAllEpisodes()
          }
        }
      },
      label: {
        Image(systemName: "checklist")
      }
    )
  }
}

// TODO: Make a preview
//#Preview {
//  EpisodeListSelectMenu()
//}
