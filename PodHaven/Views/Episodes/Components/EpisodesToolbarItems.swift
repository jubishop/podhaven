// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

// MARK: - Selectable

@MainActor @ToolbarContentBuilder
func selectableEpisodesToolbarItems<ViewModel: SelectableEpisodeList & ManagingEpisodes>(
  viewModel: ViewModel
) -> some ToolbarContent {
  if viewModel.episodeList.isSelecting, viewModel.episodeList.anySelected {
    ToolbarItem(placement: .primaryAction) {
      Menu(
        content: {
          AppIcon.playSelection.labelButton {
            viewModel.playSelectedEpisodes()
          }

          Menu {
            if viewModel.anySelectedNotQueued {
              AppIcon.addSelectionToTop.labelButton {
                viewModel.addSelectedEpisodesToTopOfQueue()
              }

              AppIcon.addSelectionToBottom.labelButton {
                viewModel.addSelectedEpisodesToBottomOfQueue()
              }

              AppIcon.replaceQueue.labelButton {
                viewModel.replaceQueueWithSelected()
              }
            } else {
              if viewModel.anySelectedNotAtTopOfQueue {
                AppIcon.moveToTop.labelButton {
                  viewModel.addSelectedEpisodesToTopOfQueue()
                }
              }

              if viewModel.anySelectedNotAtBottomOfQueue {
                AppIcon.moveToBottom.labelButton {
                  viewModel.addSelectedEpisodesToBottomOfQueue()
                }
              }
            }

            if viewModel.anySelectedQueued {
              AppIcon.removeFromQueue.labelButton {
                viewModel.dequeueSelectedEpisodes()
              }
            }
          } label: {
            AppIcon.episodeQueued.label("Queue")
          }

          Menu {
            ratingMenuButtons(showClear: viewModel.anySelectedRated) { rating in
              viewModel.rateSelectedEpisodes(rating: rating)
            }
          } label: {
            AppIcon.rateEpisode.label("Rate")
          }

          Menu {
            if viewModel.anySelectedCanStopCaching {
              AppIcon.cancelEpisodeDownload.labelButton {
                viewModel.cancelSelectedEpisodeDownloads()
              }
            }

            if viewModel.anySelectedNotCached {
              AppIcon.cacheEpisode.labelButton {
                viewModel.cacheSelectedEpisodes()
              }
            }

            if viewModel.anySelectedNotSavedInCache {
              AppIcon.saveEpisodeInCache.labelButton {
                viewModel.saveSelectedEpisodesInCache()
              }
            }

            if viewModel.anySelectedSavedInCache {
              AppIcon.unsaveEpisodeFromCache.labelButton {
                viewModel.unsaveSelectedEpisodesFromCache()
              }
            }

            if viewModel.anySelectedCanClearCache {
              AppIcon.uncacheEpisode.labelButton {
                viewModel.uncacheSelectedEpisodes()
              }
            }
          } label: {
            AppIcon.cacheEpisode.label("Cache")
          }

          if viewModel.anySelectedUnfinished {
            AppIcon.markEpisodeFinished.labelButton {
              viewModel.markSelectedEpisodesFinished()
            }
          }

          tagBulkMenu(viewModel: viewModel)
        },
        label: { AppIcon.moreActions.image }
      )
    }
  }

  ToolbarItem(placement: .primaryAction) {
    SelectableListMenu(list: viewModel.episodeList)
  }
}

// Filtered Add/Remove submenus for bulk selection.
//
// - Add Tag is `allTags - intersection(selected.tagIDs)`: any tag where at
//   least one selected episode would gain it. Tags already on every selected
//   episode are stripped so we never offer a complete no-op; per-row UNIQUE
//   hits on already-tagged episodes are demoted in the bulk action.
// - Remove Tag is `union(selected.tagIDs)`: any tag that's on at least one
//   selected episode and would actually be removed somewhere.
//
// Hidden whole-cloth when both filtered lists are empty so the menu never
// offers an action that would no-op for the entire selection — and also
// gated on `selectionHasTagData` so unsaved rows (whose tagIDs lookup is
// nil) don't expose a bulk action that would silently upsert them just to
// attach a tag, matching the per-row context-menu contract.
@MainActor @ViewBuilder
private func tagBulkMenu<ViewModel: SelectableEpisodeList & ManagingEpisodes>(
  viewModel: ViewModel
) -> some View {
  if viewModel.selectionHasTagData {
    let allTags = Container.shared.sharedState().tags
    let intersection = viewModel.selectedEpisodesTagIntersection
    let union = viewModel.selectedEpisodesTagUnion
    let addable = allTags.filter { !intersection.contains($0.id) }
    let removable = allTags.filter { union.contains($0.id) }

    if !addable.isEmpty || !removable.isEmpty {
      Menu {
        if !addable.isEmpty {
          Menu {
            ForEach(addable) { tag in
              Button(tag.name) {
                viewModel.applyTagToSelectedEpisodes(tag.id)
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
                viewModel.removeTagFromSelectedEpisodes(tag.id)
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

// MARK: - Sortable

@MainActor @ToolbarContentBuilder
func sortableEpisodesToolbarItems<ViewModel: SortableEpisodeList>(viewModel: ViewModel)
  -> some ToolbarContent
{
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
}
