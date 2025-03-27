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
        AllFieldsResultsView(
          viewModel: AllFieldsResultsViewModel(
            searchText: viewModel.termSearchResult.searchedText,
            termResult: viewModel.termSearchResult.termResult
          )
        )
      case .titles:
        TitleResultsView(
          viewModel: TitleResultsViewModel(
            searchText: viewModel.titleSearchResult.searchedText,
            titleResult: viewModel.titleSearchResult.titleResult
          )
        )
      case .people:
        PersonResultsView()
      case .trending:
        TrendingResultsView(
          viewModel:
            TrendingResultsViewModel(
              category: viewModel.trendingSearchResult.searchedCategory,
              trendingResult: viewModel.trendingSearchResult.trendingResult
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
