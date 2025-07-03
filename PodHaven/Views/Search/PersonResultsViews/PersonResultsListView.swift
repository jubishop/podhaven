// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

struct PersonResultsListView: View {
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: PersonResultsListViewModel

  init(viewModel: PersonResultsListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      HStack {
        SearchBar(
          text: $viewModel.episodeList.entryFilter,
          placeholder: "Filter episodes",
          imageName: "line.horizontal.3.decrease.circle"
        )

        Menu(
          content: {
            Button(viewModel.unplayedOnly ? "Show All" : "Unplayed Only") {
              viewModel.unplayedOnly.toggle()
            }
          },
          label: {
            Image(systemName: "line.horizontal.3.decrease.circle")
          }
        )
      }
      .padding(.horizontal)

      List(viewModel.episodeList.filteredEntries) { unsavedPodcastEpisode in
        NavigationLink(
          value: SearchedPodcastEpisode(
            searchedText: viewModel.searchText,
            unsavedPodcastEpisode: unsavedPodcastEpisode
          ),
          label: {
            EpisodeResultsListView(
              viewModel: EpisodeResultsListViewModel(
                isSelected: $viewModel.episodeList.isSelected[unsavedPodcastEpisode],
                item: unsavedPodcastEpisode.unsavedEpisode,
                isSelecting: viewModel.episodeList.isSelecting
              )
            )
          }
        )
        .episodeQueueableSwipeActions(viewModel: viewModel, episode: unsavedPodcastEpisode)
      }
      .animation(.default, value: viewModel.episodeList.filteredEntries)
    }
    .navigationDestination(
      for: SearchedPodcastEpisode.self,
      destination: navigation.episodeResultsDetailView
    )
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var viewModel: PersonResultsListViewModel?

  NavigationStack {
    if let viewModel {
      PersonResultsListView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let personResult = try! await PreviewHelpers.loadPersonResult()
    viewModel = PersonResultsListViewModel(
      searchResult: PersonSearchResult(
        searchText: "Neil deGrasse Tyson",
        personResult: personResult
      )
    )
  }
}
#endif
