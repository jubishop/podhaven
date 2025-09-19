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
            if viewModel.anySelectedNotQueued {
              Button("Add To Top Of Queue") {
                viewModel.addSelectedEpisodesToTopOfQueue()
              }
              Button("Add To Bottom Of Queue") {
                viewModel.addSelectedEpisodesToBottomOfQueue()
              }
              Button("Replace Queue") {
                viewModel.replaceQueueWithSelected()
              }
              Button("Replace Queue and Play") {
                viewModel.replaceQueueWithSelectedAndPlay()
              }
            } else {
              Button("Move To Top Of Queue") {
                viewModel.addSelectedEpisodesToTopOfQueue()
              }
              Button("Move To Bottom Of Queue") {
                viewModel.addSelectedEpisodesToBottomOfQueue()
              }
            }

            if viewModel.anySelectedQueued {
              Button("Remove From Queue") {
                viewModel.dequeueSelectedEpisodes()
              }
            }

            if viewModel.anySelectedUnfinished {
              Button("Mark Finished") {
                viewModel.markSelectedEpisodesFinished()
              }
            }

            if viewModel.anySelectedCanStopCaching {
              Button("Cancel Downloads") {
                viewModel.cancelSelectedEpisodeDownloads()
              }
            }

            if viewModel.anySelectedNotCached {
              Button("Cache Selected") {
                viewModel.cacheSelectedEpisodes()
              }
            }

            if viewModel.anySelectedCanClearCache {
              Button("Remove Downloads") {
                viewModel.uncacheSelectedEpisodes()
              }
            }
          },
          label: {
            AppLabel.queueActions.image
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
