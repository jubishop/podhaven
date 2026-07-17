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

          if viewModel.selectionHasTagData {
            TagMenu(
              intersection: viewModel.selectedPodcastsTagIntersection,
              union: viewModel.selectedPodcastsTagUnion,
              onAdd: { viewModel.applyTagToSelectedPodcasts($0) },
              onRemove: { viewModel.removeTagFromSelectedPodcasts($0) }
            )
          }

          Divider()

          if viewModel.anySelectedSaved {
            AppIcon.delete.labelButton {
              viewModel.deleteSelectedPodcasts()
            }
          }
        },
        label: {
          AppIcon.moreActions.label
            .labelStyle(.iconOnly)
        }
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
      label: {
        viewModel.currentSortMethod.appIcon
          .label("Sort")
          .labelStyle(.iconOnly)
      }
    )
    .accessibilityValue(viewModel.currentSortMethod.appIcon.text)
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
