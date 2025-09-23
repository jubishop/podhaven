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
            .tint(.green)

            if viewModel.anySelectedNotQueued {
              Button(
                action: { viewModel.addSelectedEpisodesToTopOfQueue() },
                label: { AppLabel.addSelectionToTop.label }
              )
              .tint(.blue)
              Button(
                action: { viewModel.addSelectedEpisodesToBottomOfQueue() },
                label: { AppLabel.addSelectionToBottom.label }
              )
              .tint(.purple)
              Button(
                action: { viewModel.replaceQueueWithSelected() },
                label: { AppLabel.replaceQueue.label }
              )
              .tint(.indigo)
            } else {
              if viewModel.anySelectedNotAtTopOfQueue {
                Button(
                  action: { viewModel.addSelectedEpisodesToTopOfQueue() },
                  label: { AppLabel.moveToTop.label }
                )
                .tint(.blue)
              }
              if viewModel.anySelectedNotAtBottomOfQueue {
                Button(
                  action: { viewModel.addSelectedEpisodesToBottomOfQueue() },
                  label: { AppLabel.moveToBottom.label }
                )
                .tint(.purple)
              }
            }

            if viewModel.anySelectedQueued {
              Button(
                action: { viewModel.dequeueSelectedEpisodes() },
                label: { AppLabel.removeFromQueue.label }
              )
              .tint(.red)
            }

            if viewModel.anySelectedUnfinished {
              Button(
                action: { viewModel.markSelectedEpisodesFinished() },
                label: { AppLabel.markEpisodeFinished.label }
              )
              .tint(.mint)
            }

            if viewModel.anySelectedCanStopCaching {
              Button(
                action: { viewModel.cancelSelectedEpisodeDownloads() },
                label: { AppLabel.cancelEpisodeDownload.label }
              )
              .tint(.orange)
            }

            if viewModel.anySelectedNotCached {
              Button(
                action: { viewModel.cacheSelectedEpisodes() },
                label: { AppLabel.cacheEpisode.label }
              )
              .tint(.blue)
            }

            if viewModel.anySelectedCanClearCache {
              Button(
                action: { viewModel.uncacheSelectedEpisodes() },
                label: { AppLabel.uncacheEpisode.label }
              )
              .tint(.red)
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
