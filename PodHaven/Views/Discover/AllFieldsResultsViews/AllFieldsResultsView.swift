// Copyright Justin Bishop, 2025

import SwiftUI

struct AllFieldsResultsView: View {
  private let viewModel: AllFieldsResultsViewModel

  init(viewModel: AllFieldsResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      if viewModel.termResult != nil {
        List {
          ForEach(viewModel.unsavedPodcasts, id: \.feedURL) { unsavedPodcast in
            NavigationLink(
              value: SearchedPodcastByTerm(
                searchText: viewModel.searchText,
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
                context: termPodcast
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
  @Previewable @State var viewModel: AllFieldsResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      AllFieldsResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let termResult = try! await PreviewHelpers.loadTermResult()
    viewModel = AllFieldsResultsViewModel(
      searchResult: TermSearchResult(searchedText: "Hard Fork", termResult: termResult)
    )
  }
}
