// Copyright Justin Bishop, 2025

import SwiftUI

struct QueueableSelectableEpisodesToolbarModifier<
  ViewModel: QueueableSelectableList & SelectableModel,
  EpisodeList: SelectableList
>: ViewModifier {
  @Binding private var viewModel: ViewModel
  @Binding private var episodeList: EpisodeList
  private let selectText: String

  init(viewModel: Binding<ViewModel>, episodeList: Binding<EpisodeList>, selectText: String) {
    self._viewModel = viewModel
    self._episodeList = episodeList
    self.selectText = selectText
  }

  func body(content: Content) -> some View {
    content
      .toolbar {
        if viewModel.isSelecting {
          ToolbarItem(placement: .topBarTrailing) {
            SelectableListMenu(list: episodeList)
          }
        }

        if viewModel.isSelecting, episodeList.anySelected {
          ToolbarItem(placement: .topBarTrailing) {
            QueueableSelectableListMenu(list: viewModel)
          }
        }

        if viewModel.isSelecting {
          ToolbarItem(placement: .topBarLeading) {
            Button("Done") {
              viewModel.isSelecting = false
            }
          }
        } else {
          ToolbarItem(placement: .topBarTrailing) {
            Button(selectText) {
              viewModel.isSelecting = true
            }
          }
        }
      }
      .toolbarRole(.editor)
  }
}

extension View {
  func queueableSelectableEpisodesToolbar<
    ViewModel: QueueableSelectableList & SelectableModel,
    EpisodeList: SelectableList
  >(
    viewModel: Binding<ViewModel>,
    episodeList: Binding<EpisodeList>,
    selectText: String = "Select"
  ) -> some View {
    self.modifier(
      QueueableSelectableEpisodesToolbarModifier(
        viewModel: viewModel,
        episodeList: episodeList,
        selectText: selectText
      )
    )
  }
}
