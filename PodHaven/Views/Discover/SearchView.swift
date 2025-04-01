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
          viewModel: ResultsViewModel(searchResult: viewModel.termSearchResult)
        )
      case .titles:
        TitleResultsView(
          viewModel: ResultsViewModel(searchResult: viewModel.titleSearchResult)
        )
      case .people:
        PersonResultsView(
          viewModel: PersonResultsViewModel(searchResult: viewModel.personSearchResult)
        )
      case .trending:
        TrendingResultsView(
          viewModel: ResultsViewModel(searchResult: viewModel.trendingSearchResult)
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
