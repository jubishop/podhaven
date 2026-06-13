// Copyright Justin Bishop, 2025

import SwiftUI

// MARK: - Selectable

@MainActor @ToolbarContentBuilder
func selectableEpisodesToolbarItems<ViewModel: SelectableEpisodeList & ManagingEpisodes>(
  viewModel: ViewModel
) -> some ToolbarContent {
  if viewModel.isSelecting, viewModel.anySelected {
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

          AppIcon.transcribeEpisode.labelButton {
            viewModel.transcribeSelectedEpisodes()
          }

          if viewModel.selectionHasTagData {
            TagMenu(
              intersection: viewModel.selectedEpisodesTagIntersection,
              union: viewModel.selectedEpisodesTagUnion,
              onAdd: { viewModel.applyTagToSelectedEpisodes($0) },
              onRemove: { viewModel.removeTagFromSelectedEpisodes($0) }
            )
          }
        },
        label: { AppIcon.moreActions.image }
      )
    }
  }

  ToolbarItem(placement: .primaryAction) {
    SelectableListMenu(list: viewModel)
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
