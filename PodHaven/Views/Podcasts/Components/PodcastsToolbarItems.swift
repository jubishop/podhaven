// Copyright Justin Bishop, 2025

import SwiftUI

// MARK: - Selectable

@MainActor @ToolbarContentBuilder
func selectablePodcastsToolbarItems<ViewModel: SelectablePodcastList>(viewModel: ViewModel)
  -> some ToolbarContent
{
  if viewModel.podcastList.isSelecting, viewModel.podcastList.anySelected {
    ToolbarItem(placement: .primaryAction) {
      Menu(
        content: {
          if viewModel.anySelectedUnsubscribed {
            AppIcon.subscribe.labelButton {
              viewModel.subscribeSelectedPodcasts()
            }
          }

          if viewModel.anySelectedSubscribed {
            AppIcon.unsubscribe.labelButton {
              viewModel.unsubscribeSelectedPodcasts()
            }
          }

          Divider()

          if viewModel.anySelectedSaved {
            AppIcon.delete.labelButton {
              viewModel.deleteSelectedPodcasts()
            }
          }
        },
        label: { AppIcon.moreActions.image }
      )
    }
  }

  ToolbarItem(placement: .primaryAction) {
    SelectableListMenu(list: viewModel.podcastList)
  }
}

// MARK: - Sortable

@MainActor @ToolbarContentBuilder
func sortablePodcastsToolbarItems<ViewModel: SortablePodcastList>(viewModel: ViewModel)
  -> some ToolbarContent
{
  ToolbarItem(placement: .primaryAction) {
    Menu(
      content: { sortablePodcastsToolbarMenuItems(viewModel: viewModel) },
      label: { viewModel.currentSortMethod.appIcon.image }
    )
  }
}

// MARK: - Sortable & Displaying

@MainActor @ToolbarContentBuilder
func sortableDisplayingPodcastsToolbarItems<ViewModel: SortablePodcastList & DisplayingPodcasts>(
  viewModel: ViewModel
) -> some ToolbarContent {
  ToolbarItem(placement: .primaryAction) {
    Menu(
      content: {
        sortablePodcastsToolbarMenuItems(viewModel: viewModel)

        Divider()

        (viewModel.displayMode == .grid ? AppIcon.list : AppIcon.grid)
          .labelButton {
            viewModel.toggleDisplayMode()
          }
      },
      label: { viewModel.currentSortMethod.appIcon.image }
    )
  }
}

// MARK: - Private Helpers

@MainActor @ViewBuilder
private func sortablePodcastsToolbarMenuItems<ViewModel: SortablePodcastList>(viewModel: ViewModel)
  -> some View
{
  ForEach(viewModel.allSortMethods, id: \.self) { sortMethod in
    sortMethod.appIcon
      .labelButton {
        viewModel.currentSortMethod = sortMethod
      }
      .disabled(viewModel.currentSortMethod == sortMethod)
  }
}
