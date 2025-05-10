// Copyright Justin Bishop, 2025

import SwiftUI

struct QueueableSelectableEpisodesToolbarModifier<
  ViewModel: QueueableSelectableList,
  EpisodeList: SelectableList
>: ViewModifier {
  @Binding private var episodeList: EpisodeList
  private let viewModel: ViewModel

  init(viewModel: ViewModel, episodeList: Binding<EpisodeList>) {
    self.viewModel = viewModel
    self._episodeList = episodeList
  }

  func body(content: Content) -> some View {
    content
      .toolbar {
        if episodeList.isSelecting {
          ToolbarItem(placement: .topBarTrailing) {
            SelectableListMenu(list: episodeList)
          }
        }

        if episodeList.isSelecting, episodeList.anySelected {
          ToolbarItem(placement: .topBarTrailing) {
            QueueableSelectableListMenu(list: viewModel)
          }
        }

        if episodeList.isSelecting {
          ToolbarItem(placement: .topBarLeading) {
            Button("Done") {
              episodeList.isSelecting = false
            }
          }
        } else {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Select Episodes") {
              episodeList.isSelecting = true
            }
          }
        }
      }
      .toolbarRole(.editor)
  }
}

extension View {
  func queueableSelectableEpisodesToolbar<
    ViewModel: QueueableSelectableList,
    EpisodeList: SelectableList
  >(
    viewModel: ViewModel,
    episodeList: Binding<EpisodeList>
  ) -> some View {
    self.modifier(
      QueueableSelectableEpisodesToolbarModifier(viewModel: viewModel, episodeList: episodeList)
    )
  }
}
