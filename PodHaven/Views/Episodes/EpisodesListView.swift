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
    SearchBar(
      text: $viewModel.episodeList.entryFilter,
      placeholder: "Filter episodes",
      imageName: AppLabel.filter.systemImageName
    )
    .padding(.horizontal)

    List(viewModel.episodeList.filteredEntries) { podcastEpisode in
      NavigationLink(
        value: Navigation.Destination.episode(DisplayedEpisode(podcastEpisode)),
        label: {
          EpisodeListView(
            episode: podcastEpisode,
            isSelecting: viewModel.isSelecting,
            isSelected: $viewModel.episodeList.isSelected[podcastEpisode.id]
          )
        }
      )
      .episodeListRow()
      .episodeSwipeActions(viewModel: viewModel, episode: podcastEpisode)
      .episodeContextMenu(viewModel: viewModel, episode: podcastEpisode) {
        AppLabel.showPodcast.labelButton {
          viewModel.showPodcast(podcastEpisode)
        }
      }
    }
    .playBarSafeAreaInset()
    .animation(.default, value: viewModel.episodeList.filteredEntries)
    .navigationTitle(viewModel.title)
    .toolbar {
      selectableEpisodesToolbarItems(
        viewModel: viewModel,
        episodeList: viewModel.episodeList
      )
    }
    .toolbarRole(.editor)
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    EpisodesListView(
      viewModel: EpisodesListViewModel(title: "Finished", filter: Episode.finished)
    )
  }
  .preview()
  .task { try? await PreviewHelpers.populateFinishedPodcastEpisodes() }
}
#endif
