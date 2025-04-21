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
      default: fatalError("viewModel.currentView unknown: \(viewModel.currentView)")
      }
    }
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    SearchView(viewModel: DiscoverViewModel())
  }
  .preview()
}
#endif
