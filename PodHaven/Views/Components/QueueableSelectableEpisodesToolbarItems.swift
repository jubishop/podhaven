// Copyright Justin Bishop, 2025

import SwiftUI

@MainActor
struct QueueableSelectableEpisodesToolbarItems<
  ViewModel: QueueableSelectableListModel,
  EpisodeList: SelectableList
> {
  let viewModel: Binding<ViewModel>
  let episodeList: Binding<EpisodeList>
  let selectText: String

  init(
    viewModel: Binding<ViewModel>,
    episodeList: Binding<EpisodeList>,
    selectText: String = "Select"
  ) {
    self.viewModel = viewModel
    self.episodeList = episodeList
    self.selectText = selectText
  }

  @ToolbarContentBuilder
  var content: some ToolbarContent {
    if viewModel.wrappedValue.isSelecting {
      ToolbarItem(placement: .topBarTrailing) {
        SelectableListMenu(list: episodeList.wrappedValue)
      }
    }

    if viewModel.wrappedValue.isSelecting, episodeList.wrappedValue.anySelected {
      ToolbarItem(placement: .topBarTrailing) {
        QueueableSelectableListMenu(list: viewModel.wrappedValue)
      }
    }

    if viewModel.wrappedValue.isSelecting {
      ToolbarItem(placement: .topBarLeading) {
        Button("Done") {
          viewModel.wrappedValue.isSelecting = false
        }
      }
    } else {
      ToolbarItem(placement: .topBarTrailing) {
        Button(selectText) {
          viewModel.wrappedValue.isSelecting = true
        }
      }
    }
  }
}

// Convenience function to create toolbar content
@MainActor
func queueableSelectableEpisodesToolbarItems<
  ViewModel: QueueableSelectableListModel,
  EpisodeList: SelectableList
>(
  viewModel: Binding<ViewModel>,
  episodeList: Binding<EpisodeList>,
  selectText: String = "Select"
) -> some ToolbarContent {
  QueueableSelectableEpisodesToolbarItems(
    viewModel: viewModel,
    episodeList: episodeList,
    selectText: selectText
  ).content
}
