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
      trendingResult: try! await SearchService.parseForPreview(
        try! Data(
          contentsOf: Bundle.main.url(forResource: "trending_in_news", withExtension: "json")!
        )
      )
    )
  }
}
