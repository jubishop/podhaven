// Copyright Justin Bishop, 2025

import SwiftUI

struct PodcastsResultsView: View {
  private let viewModel: ResultsViewModel

  init(viewModel: ResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      if viewModel.result != nil {
        List {
          ForEach(viewModel.unsavedPodcasts, id: \.feedURL) { unsavedPodcast in
            NavigationLink(
              value: SearchedPodcast(
                searchedText: viewModel.searchText,
                unsavedPodcast: unsavedPodcast
              ),
              label: {
                PodcastResultsListView(unsavedPodcast: unsavedPodcast)
              }
            )
          }
        }
        .navigationDestination(
          for: SearchedPodcast.self,
          destination: { searchedPodcast in
            PodcastResultsDetailView(viewModel: PodcastResultsDetailViewModel(searchedPodcast: searchedPodcast))
          }
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle(viewModel.title)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var viewModel: ResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      PodcastsResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let termResult = try! await PreviewHelpers.loadTermResult()
    viewModel = ResultsViewModel(
      title: "🔍📖 Hard Fork",
      searchResult: PodcastSearchResult(searchText: "Hard Fork", result: termResult)
    )
  }
}
#endif
