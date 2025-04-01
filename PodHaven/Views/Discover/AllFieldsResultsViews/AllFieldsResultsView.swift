// Copyright Justin Bishop, 2025

import SwiftUI

struct AllFieldsResultsView: View {
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
              value: SearchedPodcastByTerm(
                searchedText: viewModel.searchText,
                unsavedPodcast: unsavedPodcast
              ),
              label: {
                AllFieldsPodcastListView(unsavedPodcast: unsavedPodcast)
              }
            )
          }
        }
        .navigationDestination(
          for: SearchedPodcastByTerm.self,
          destination: { termPodcast in
            AllFieldsPodcastView(
              viewModel: PodcastResultsViewModel(
                searchedPodcast: termPodcast
              )
            )
          }
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle("🔍📖 \(viewModel.searchText)")
  }
}

#Preview {
  @Previewable @State var viewModel: ResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      AllFieldsResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let termResult = try! await PreviewHelpers.loadTermResult()
    viewModel = ResultsViewModel(
      searchResult: TermSearchResult(searchText: "Hard Fork", termResult: termResult)
    )
  }
}
