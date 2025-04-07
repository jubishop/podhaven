// Copyright Justin Bishop, 2025

import SwiftUI

struct ResultsContentView<SearchedPodcastType: SearchedPodcast>: View {
  private let viewModel: ResultsViewModel
  private let createSearchedPodcast: (String, UnsavedPodcast) -> SearchedPodcastType
  
  init(
    viewModel: ResultsViewModel,
    createSearchedPodcast: @escaping (String, UnsavedPodcast) -> SearchedPodcastType
  ) {
    self.viewModel = viewModel
    self.createSearchedPodcast = createSearchedPodcast
  }
  
  var body: some View {
    VStack {
      if viewModel.result != nil {
        List {
          ForEach(viewModel.unsavedPodcasts, id: \.feedURL) { unsavedPodcast in
            NavigationLink(
              value: createSearchedPodcast(
                viewModel.searchText,
                unsavedPodcast
              ),
              label: {
                PodcastListResultsView(unsavedPodcast: unsavedPodcast)
              }
            )
          }
        }
        .navigationDestination(
          for: SearchedPodcastType.self,
          destination: { searchedPodcast in
            PodcastResultsView(
              viewModel: PodcastResultsViewModel(
                searchedPodcast: searchedPodcast
              )
            )
          }
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
  }
}
