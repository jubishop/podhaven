// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct StandardEpisodesView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: StandardEpisodesViewModel

  init(viewModel: StandardEpisodesViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    List(viewModel.episodeList.allEntries) { podcastEpisode in
      NavigationLink(
        value: Navigation.Episodes.Destination.episode(podcastEpisode),
        label: {
          PodcastEpisodeListView(
            viewModel: PodcastEpisodeListViewModel(
              isSelected: $viewModel.episodeList.isSelected[podcastEpisode],
              item: podcastEpisode,
              isSelecting: viewModel.episodeList.isSelecting
            )
          )
        }
      )
      .episodeQueueableSwipeActions(viewModel: viewModel, episode: podcastEpisode)
    }
    .animation(.default, value: viewModel.episodeList.filteredEntries)
    .navigationTitle(viewModel.title)
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    StandardEpisodesView(
      viewModel: StandardEpisodesViewModel(title: "Completed", filter: Episode.completed)
    )
  }
  .preview()
  .task { try? await PreviewHelpers.populateCompletedPodcastEpisodes() }
}
#endif
