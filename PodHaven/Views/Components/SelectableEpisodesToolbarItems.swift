// Copyright Justin Bishop, 2025

import SwiftUI

@MainActor
struct SelectableEpisodesToolbarItems<
  ViewModel: SelectableEpisodeList,
  EpisodeList: SelectableList
> {
  let viewModel: ViewModel
  let episodeList: EpisodeList
  let selectText: String

  init(
    viewModel: ViewModel,
    episodeList: EpisodeList,
    selectText: String = "Select"
  ) {
    self.viewModel = viewModel
    self.episodeList = episodeList
    self.selectText = selectText
  }

  @ToolbarContentBuilder
  var content: some ToolbarContent {
    if viewModel.isSelecting {
      ToolbarItem(placement: .topBarTrailing) {
        SelectableListMenu(list: episodeList)
      }
    }

    if viewModel.isSelecting, episodeList.anySelected {
      ToolbarItem(placement: .topBarTrailing) {
        Menu(
          content: {
            Button(
              action: { viewModel.playSelectedEpisodes() },
              label: { AppLabel.playSelection.label }
            )

            if viewModel.anySelectedNotQueued {
              Button(
                action: { viewModel.addSelectedEpisodesToTopOfQueue() },
                label: { AppLabel.addSelectionToTop.label }
              )
              Button(
                action: { viewModel.addSelectedEpisodesToBottomOfQueue() },
                label: { AppLabel.addSelectionToBottom.label }
              )
              Button(
                action: { viewModel.replaceQueueWithSelected() },
                label: { AppLabel.replaceQueue.label }
              )
            } else {
              if viewModel.anySelectedNotAtTopOfQueue {
                Button(
                  action: { viewModel.addSelectedEpisodesToTopOfQueue() },
                  label: { AppLabel.moveToTop.label }
                )
              }
              if viewModel.anySelectedNotAtBottomOfQueue {
                Button(
                  action: { viewModel.addSelectedEpisodesToBottomOfQueue() },
                  label: { AppLabel.moveToBottom.label }
                )
              }
            }

            if viewModel.anySelectedQueued {
              Button(
                action: { viewModel.dequeueSelectedEpisodes() },
                label: { AppLabel.removeFromQueue.label }
              )
            }

            if viewModel.anySelectedUnfinished {
              Button(
                action: { viewModel.markSelectedEpisodesFinished() },
                label: { AppLabel.markEpisodeFinished.label }
              )
            }

            if viewModel.anySelectedCanStopCaching {
              Button(
                action: { viewModel.cancelSelectedEpisodeDownloads() },
                label: { AppLabel.cancelEpisodeDownload.label }
              )
            }

            if viewModel.anySelectedNotCached {
              Button(
                action: { viewModel.cacheSelectedEpisodes() },
                label: { AppLabel.cacheEpisode.label }
              )
            }

            if viewModel.anySelectedCanClearCache {
              Button(
                action: { viewModel.uncacheSelectedEpisodes() },
                label: { AppLabel.uncacheEpisode.label }
              )
            }
          },
          label: {
            AppLabel.moreActions.image
          }
        )
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
}

@MainActor
func selectableEpisodesToolbarItems<
  ViewModel: SelectableEpisodeList,
  EpisodeList: SelectableList
>(
  viewModel: ViewModel,
  episodeList: EpisodeList,
  selectText: String = "Select"
) -> some ToolbarContent {
  SelectableEpisodesToolbarItems(
    viewModel: viewModel,
    episodeList: episodeList,
    selectText: selectText
  )
  .content
}
