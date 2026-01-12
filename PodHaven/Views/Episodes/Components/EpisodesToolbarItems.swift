// Copyright Justin Bishop, 2025

import SwiftUI

// MARK: - Selectable

@MainActor @ToolbarContentBuilder
func selectableEpisodesToolbarItems<ViewModel: SelectableEpisodeList>(viewModel: ViewModel)
  -> some ToolbarContent
{
  if viewModel.episodeList.isSelecting, viewModel.episodeList.anySelected {
    ToolbarItem(placement: .primaryAction) {
      Menu(
        content: {
          AppIcon.playSelection.labelButton {
            viewModel.playSelectedEpisodes()
          }

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

          if viewModel.anySelectedUnfinished {
            AppIcon.markEpisodeFinished.labelButton {
              viewModel.markSelectedEpisodesFinished()
            }
          }
        },
        label: { AppIcon.moreActions.image }
      )
    }
  }

  ToolbarItem(placement: .primaryAction) {
    SelectableListMenu(list: viewModel.episodeList)
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
