// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchView: View {
  private let viewModel: DiscoverViewModel

  init(viewModel: DiscoverViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    Group {
      switch viewModel.currentView {
      case .allFields:
        PodcastsResultsView(
          viewModel: ResultsViewModel(
            title: "🔍📖 \(viewModel.termSearchResult.searchText)",
            searchResult: viewModel.termSearchResult
          )
        )
      case .titles:
        PodcastsResultsView(
          viewModel: ResultsViewModel(
            title: "🔍 \(viewModel.titleSearchResult.searchText)",
            searchResult: viewModel.titleSearchResult
          )
        )
      case .people:
        PersonResultsView(
          viewModel: PersonResultsViewModel(
            title: "🕵️ \(viewModel.personSearchResult.searchText)",
            searchResult: viewModel.personSearchResult
          )
        )
      case .trending:
        PodcastsResultsView(
          viewModel: ResultsViewModel(
            title: "📈 \(viewModel.trendingSearchResult.searchText)",
            searchResult: viewModel.trendingSearchResult
          )
        )
      default: fatalError("viewModel.currentView unknown: \(viewModel.currentView)")
      }
    }
  }
}

#Preview {
  NavigationStack {
    SearchView(viewModel: DiscoverViewModel())
  }
  .preview()
}
