// Copyright Justin Bishop, 2025

import SwiftUI

struct ResultsView: View {
  private let viewModel: SearchViewModel

  init(viewModel: SearchViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    Group {
      switch viewModel.currentView {
      case .allFields:
        PodcastsResultsView(
          viewModel: ResultsViewModel(
            title: "🔍📖 \(viewModel.podcastSearchResult.searchText)",
            searchResult: viewModel.podcastSearchResult
          )
        )
      case .titles:
        PodcastsResultsView(
          viewModel: ResultsViewModel(
            title: "🔍 \(viewModel.podcastSearchResult.searchText)",
            searchResult: viewModel.podcastSearchResult
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
            title: "📈 \(viewModel.podcastSearchResult.searchText)",
            searchResult: viewModel.podcastSearchResult
          )
        )
      default: Log.fatal("viewModel.currentView unknown: \(viewModel.currentView)")
      }
    }
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    ResultsView(viewModel: SearchViewModel())
  }
  .preview()
}
#endif
