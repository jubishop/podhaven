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
        AllFieldsResultView()
          .navigationTitle("All Fields")
      case .titles:
        TitlesResultView()
          .navigationTitle("Titles")
      case .people:
        PeopleResultView()
          .navigationTitle("People")
      case .trending:
        TrendingResultView(currentTokens: viewModel.currentTokens)
          .navigationTitle("Trending")
      default: fatalError("viewModel.currentView unknown: \(viewModel.currentView)")
      }
    }
  }
}

// TODO: Make preview
