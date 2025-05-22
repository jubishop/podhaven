// Copyright Justin Bishop, 2025

import SwiftUI

struct StandardPlaylistView: View {
  @Environment(Alert.self) var alert

  @State private var viewModel: StandardPlaylistViewModel

  init(viewModel: StandardPlaylistViewModel) {
    self.viewModel = viewModel
  }

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
    .navigationTitle(viewModel.title)
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    StandardPlaylistView(
      viewModel: StandardPlaylistViewModel(title: "Completed", filter: Episode.completed)
    )
  }
  .preview()
  .task { try? await PreviewHelpers.populateCompletedPodcastEpisodes() }
}
#endif
