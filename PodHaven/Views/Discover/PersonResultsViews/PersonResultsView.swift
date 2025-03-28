// Copyright Justin Bishop, 2025

import SwiftUI

struct PersonResultsView: View {
  @State private var viewModel: PersonResultsViewModel

  init(viewModel: PersonResultsViewModel) {
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
          value: unsavedPodcastEpisode,
          label: {
            PersonEpisodeListView(
              viewModel: PersonEpisodeListViewModel(
                isSelected: $viewModel.episodeList.isSelected[unsavedPodcastEpisode],
                unsavedEpisode: unsavedPodcastEpisode.unsavedEpisode,
                isSelecting: viewModel.isSelecting
              )
            )
          }
        )
        .episodeSwipeActions(viewModel: viewModel, episode: unsavedPodcastEpisode)
      }
      .animation(.default, value: viewModel.episodeList.filteredEntries)
    }
    .navigationTitle("🕵️ \(viewModel.searchText)")
    .navigationDestination(for: UnsavedPodcastEpisode.self) { unsavedPodcastEpisode in
      PersonEpisodeView(
        viewModel: PersonEpisodeViewModel(unsavedPodcastEpisode: unsavedPodcastEpisode)
      )
    }
    .task { await viewModel.execute() }
  }
}

#Preview {
  @Previewable @State var viewModel: PersonResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      PersonResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let personResult = try! await PreviewHelpers.loadPersonResult()
    viewModel = PersonResultsViewModel(
      searchResult: PersonSearchResult(
        searchedText: "Neil deGrasse Tyson",
        personResult: personResult
      )
    )
  }
}
