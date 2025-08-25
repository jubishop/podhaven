// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct EpisodesListView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: EpisodesListViewModel

  init(viewModel: EpisodesListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    List(viewModel.episodeList.allEntries) { podcastEpisode in
      NavigationLink(
        value: Navigation.Episodes.Destination.episode(podcastEpisode),
        label: {
          PodcastEpisodeListView(
            viewModel: SelectableListItemModel(
              isSelected: $viewModel.episodeList.isSelected[podcastEpisode],
              item: podcastEpisode,
              isSelecting: viewModel.episodeList.isSelecting
            )
          )
        }
      )
      .episodeSwipeActions(viewModel: viewModel, episode: podcastEpisode)
      .episodeQueueableContextMenu(viewModel: viewModel, episode: podcastEpisode) {
        Button(action: { viewModel.showPodcast(for: podcastEpisode) }) {
          AppLabel.showPodcast.label
        }
      }
    }
    .animation(.default, value: viewModel.episodeList.allEntries)
    .navigationTitle(viewModel.title)
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    EpisodesListView(
      viewModel: EpisodesListViewModel(title: "Completed", filter: Episode.completed)
    )
  }
  .preview()
  .task { try? await PreviewHelpers.populateCompletedPodcastEpisodes() }
}
#endif
