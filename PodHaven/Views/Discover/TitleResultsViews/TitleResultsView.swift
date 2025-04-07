// Copyright Justin Bishop, 2025

import SwiftUI

struct TitleResultsView: View {
  private let viewModel: ResultsViewModel

  init(viewModel: ResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ResultsContentView<SearchedPodcastByTitle>(
      viewModel: viewModel
    ) { searchText, unsavedPodcast in
      SearchedPodcastByTitle(
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
      TitleResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let titleResult = try! await PreviewHelpers.loadTitleResult()
    viewModel = ResultsViewModel(
      searchResult: TitleSearchResult(searchText: "Hello", titleResult: titleResult)
    )
  }
}
