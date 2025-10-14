// Copyright Justin Bishop, 2025

import SwiftUI

@MainActor
struct SelectablePodcastsToolbarItems<ViewModel: SelectablePodcastList> {
  let viewModel: ViewModel

  init(viewModel: ViewModel) {
    self.viewModel = viewModel
  }

  @ToolbarContentBuilder
  var content: some ToolbarContent {
    if viewModel.isSelecting {
      ToolbarItem(placement: .primaryAction) {
        SelectableListMenu(list: viewModel.podcastList)
      }
    }

    if viewModel.isSelecting, viewModel.podcastList.anySelected {
      ToolbarItem(placement: .primaryAction) {
        Menu(
          content: {
            if viewModel.anySelectedSaved {
              Button("Delete") {
                viewModel.deleteSelectedPodcasts()
              }
            }

            if viewModel.anySelectedUnsubscribed {
              Button("Subscribe") {
                viewModel.subscribeSelectedPodcasts()
              }
            }

            if viewModel.anySelectedSubscribed {
              Button("Unsubscribe") {
                viewModel.unsubscribeSelectedPodcasts()
              }
            }
          },
          label: { AppIcon.moreActions.image }
        )
      }
    }

    if viewModel.isSelecting {
      ToolbarItem(placement: .cancellationAction) {
        Button(AppIcon.editFinished.text) {
          viewModel.isSelecting = false
        }
      }
    } else {
      ToolbarItem(placement: .primaryAction) {
        Menu(
          content: {
            ForEach(viewModel.allSortMethods, id: \.self) { sortMethod in
              sortMethod.appIcon
                .labelButton {
                  viewModel.currentSortMethod = sortMethod
                }
                .disabled(viewModel.currentSortMethod == sortMethod)
            }
          },
          label: { viewModel.currentSortMethod.appIcon.image }
        )
      }

      ToolbarItem(placement: .primaryAction) {
        Button(AppIcon.editItems.text) {
          viewModel.isSelecting = true
        }
      }
    }
  }
}

@MainActor
func selectablePodcastsToolbarItems<ViewModel: SelectablePodcastList>(viewModel: ViewModel)
  -> some ToolbarContent
{
  SelectablePodcastsToolbarItems(viewModel: viewModel).content
}
