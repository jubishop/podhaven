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
            searchText: viewModel.searchText,
            termResult: viewModel.termResult
          )
        )
      case .titles:
        TitleResultsView(
          viewModel: TitleResultsViewModel(
            searchText: viewModel.searchText,
            titleResult: viewModel.titleResult
          )
        )
      case .people:
        PeopleResultsView()
      case .trending:
        TrendingResultsView(
          viewModel:
            TrendingResultsViewModel(
              category: viewModel.currentCategory,
              trendingResult: viewModel.trendingResult
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
