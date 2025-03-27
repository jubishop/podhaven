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
          viewModel: AllFieldsResultsViewModel(searchResult: viewModel.termSearchResult)
        )
      case .titles:
        TitleResultsView(
          viewModel: TitleResultsViewModel(searchResult: viewModel.titleSearchResult)
        )
      case .people:
        PersonResultsView(
          viewModel: PersonResultsViewModel(searchResult: viewModel.personSearchResult)
        )
      case .trending:
        TrendingResultsView(
          viewModel: TrendingResultsViewModel(searchResult: viewModel.trendingSearchResult)
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
