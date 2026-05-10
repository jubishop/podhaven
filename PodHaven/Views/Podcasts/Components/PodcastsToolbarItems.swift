// Copyright Justin Bishop, 2025

import FactoryKit
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

          BulkPodcastTagMenu(viewModel: viewModel)

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

// Wrapped in a struct view (rather than a free `@ViewBuilder` function)
// so `@DynamicInjected(\.sharedState)` participates in SwiftUI observation
// tracking — tag renames/adds reflect in the open menu without waiting for
// some unrelated re-render to evict the toolbar.
@MainActor
private struct BulkPodcastTagMenu<ViewModel: SelectablePodcastList>: View {
  @DynamicInjected(\.sharedState) private var sharedState

  let viewModel: ViewModel

  var body: some View {
    if viewModel.selectionHasTagData {
      let allTags = sharedState.tags
      let intersection = viewModel.selectedPodcastsTagIntersection
      let union = viewModel.selectedPodcastsTagUnion
      let addable = allTags.filter { !intersection.contains($0.id) }
      let removable = allTags.filter { union.contains($0.id) }

      if !addable.isEmpty || !removable.isEmpty {
        Menu {
          if !addable.isEmpty {
            Menu {
              ForEach(addable) { tag in
                Button(tag.name) {
                  viewModel.applyTagToSelectedPodcasts(tag.id)
                }
              }
            } label: {
              AppIcon.addTag.label("Add Tag")
            }
          }

          if !removable.isEmpty {
            Menu {
              ForEach(removable) { tag in
                Button(tag.name) {
                  viewModel.removeTagFromSelectedPodcasts(tag.id)
                }
              }
            } label: {
              AppIcon.removeTag.label("Remove Tag")
            }
          }
        } label: {
          AppIcon.tag.label("Tag")
        }
      }
    }
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
