// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct CompletedView: View {
  @Environment(Alert.self) var alert

  @State private var navigation = Container.shared.navigation()
  @State private var viewModel = CompletedViewModel()

  var body: some View {
    List(viewModel.episodeList.allEntries) { podcastEpisode in
      PodcastEpisodeListView(
        viewModel: PodcastEpisodeListViewModel(
          isSelected: $viewModel.episodeList.isSelected[podcastEpisode],
          item: podcastEpisode,
          isSelecting: viewModel.episodeList.isSelecting
        )
      )
      .episodeQueueableSwipeActions(viewModel: viewModel, episode: podcastEpisode)
    }
    .animation(.default, value: viewModel.episodeList.filteredEntries)
    .navigationTitle("Completed Episodes")
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task { await viewModel.execute() }
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    CompletedView()
  }
  .preview()
  .task { try? await PreviewHelpers.populateCompletedPodcastEpisodes() }
}
#endif
