// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingResultsView: View {
  private let viewModel: ResultsViewModel

  init(viewModel: ResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ResultsContentView<SearchedPodcastByTrending>(
      viewModel: viewModel
    ) { searchText, unsavedPodcast in
      SearchedPodcastByTrending(
        category: searchText,
        unsavedPodcast: unsavedPodcast
      )
    }
    .navigationTitle("📈 \(viewModel.searchText)")
  }
}

#Preview {
  @Previewable @State var viewModel: ResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      TrendingResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let trendingResult = try! await PreviewHelpers.loadTrendingResult()
    viewModel = ResultsViewModel(
      searchResult: TrendingSearchResult(searchCategory: "News", trendingResult: trendingResult)
    )
  }
}
