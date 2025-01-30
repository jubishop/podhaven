// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingResultsView: View {
  private let viewModel: TrendingResultsViewModel

  init(viewModel: TrendingResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      Text(viewModel.category)
        .font(.largeTitle)
      List {
        ForEach(viewModel.unsavedPodcasts) { unsavedPodcast in
          TrendingItemListView(unsavedPodcast: unsavedPodcast)
        }
      }
      .navigationDestination(for: UnsavedPodcast) { unsavedPodcast in
        TrendingItemDetailView(
          viewModel: TrendingItemDetailViewModel(
            category: viewModel.category,
            unsavedPodcast: unsavedPodcast
          )
        )
      }
    }
    .navigationTitle("Trending")
  }
}

#Preview {
  @Previewable @State var viewModel: TrendingResultsViewModel = TrendingResultsViewModel(
    category: "News",
    trendingResult: nil
  )

  NavigationStack {
    TrendingResultsView(viewModel: viewModel)
  }
  .preview()
  .task {
    viewModel = TrendingResultsViewModel(
      category: "News",
      trendingResult: try! await PreviewHelpers.loadTrendingResult()
    )
  }
}
