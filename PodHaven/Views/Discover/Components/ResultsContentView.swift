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

#Preview {
  @Previewable @State var viewModel: ResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      ResultsContentView<SearchedPodcastByTerm>(
        viewModel: viewModel
      ) { searchText, unsavedPodcast in
        SearchedPodcastByTerm(
          searchedText: searchText,
          unsavedPodcast: unsavedPodcast
        )
      }
      .navigationTitle("🔍 Preview")
    }
  }
  .preview()
  .task {
    let termResult = try! await PreviewHelpers.loadTermResult()
    viewModel = ResultsViewModel(
      searchResult: TermSearchResult(searchText: "Preview Test", termResult: termResult)
    )
  }
}
