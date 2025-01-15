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
      if let trendingResult = viewModel.trendingResult {
        List {
          ForEach(trendingResult.feeds) { feed in
            TrendingItemListView(feedResult: feed)
          }
        }
        .navigationDestination(for: TrendingResult.FeedResult.self) { feedResult in
          TrendingItemDetailView(
            viewModel: TrendingItemDetailViewModel(
              category: viewModel.category,
              feedResult: feedResult
            )
          )
        }
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle("Trending")
  }
}

// TODO: Make a preview
