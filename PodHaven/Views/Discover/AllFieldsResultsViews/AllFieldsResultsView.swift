// Copyright Justin Bishop, 2025

import SwiftUI

struct AllFieldsResultsView: View {
  private let viewModel: ResultsViewModel

  init(viewModel: ResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ResultsContentView<SearchedPodcastByTerm>(
      viewModel: viewModel
    ) { searchText, unsavedPodcast in
      SearchedPodcastByTerm(
        searchedText: searchText,
        unsavedPodcast: unsavedPodcast
      )
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
