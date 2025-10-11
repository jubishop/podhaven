// Copyright Justin Bishop, 2025

import SwiftUI

@MainActor
struct SelectableEpisodesToolbarItems<
  ViewModel: SelectableEpisodeList,
  EpisodeList: SelectableList
> {
  let viewModel: ViewModel
  let episodeList: EpisodeList

  init(
    viewModel: ViewModel,
    episodeList: EpisodeList
  ) {
    self.viewModel = viewModel
    self.episodeList = episodeList
  }

  @ToolbarContentBuilder
  var content: some ToolbarContent {
    if viewModel.isSelecting {
      ToolbarItem(placement: .primaryAction) {
        SelectableListMenu(list: episodeList)
      }
    }

    if viewModel.isSelecting, episodeList.anySelected {
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

    if viewModel.isSelecting {
      ToolbarItem(placement: .cancellationAction) {
        Button(AppIcon.editFinished.text) {
          viewModel.isSelecting = false
        }
      }
    } else {
      ToolbarItem(placement: .primaryAction) {
        Button(AppIcon.selectItems.text) {
          viewModel.isSelecting = true
        }
      }
    }
  }
}

@MainActor
func selectableEpisodesToolbarItems<
  ViewModel: SelectableEpisodeList,
  EpisodeList: SelectableList
>(
  viewModel: ViewModel,
  episodeList: EpisodeList
) -> some ToolbarContent {
  SelectableEpisodesToolbarItems(
    viewModel: viewModel,
    episodeList: episodeList
  )
  .content
}
