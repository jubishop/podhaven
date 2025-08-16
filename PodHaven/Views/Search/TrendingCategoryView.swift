// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct TrendingCategoryView: View {
  @DynamicInjected(\.alert) private var alert

  @State private var viewModel: TrendingCategoryViewModel

  init(category: String) {
    _viewModel = State(initialValue: TrendingCategoryViewModel(category: category))
  }

  var body: some View {
    ScrollView {
      switch viewModel.state {
      case .loading:
        ProgressView("Loading \(viewModel.category) podcasts...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding()

      case .loaded(let searchedPodcasts):
        ItemGrid(items: searchedPodcasts.map { $0.toUnsavedPodcast() }) { unsavedPodcast in
          SearchedPodcastGridItem(
            viewModel: SearchedPodcastGridItemViewModel(unsavedPodcast: unsavedPodcast)
          )
        }
        .padding()

      case .error(let message):
        VStack {
          Text("Error")
            .font(.headline)
          Text(message)
            .foregroundColor(.secondary)
        }
        .padding()
      }
    }
    .navigationTitle(viewModel.category)
    .navigationBarTitleDisplayMode(.large)
    .task {
      await viewModel.loadPodcasts()
    }
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    TrendingCategoryView(category: "Technology")
  }
  .preview()
}
#endif
