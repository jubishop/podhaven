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
      if viewModel.trendingResult != nil {
        List {
          ForEach(viewModel.unsavedPodcasts, id: \.feedURL) { unsavedPodcast in
            NavigationLink(
              value: TrendingPodcast(
                unsavedPodcast: unsavedPodcast,
                category: viewModel.category
              ),
              label: {
                TrendingItemListView(unsavedPodcast: unsavedPodcast)
              }
            )
          }
        }
        .navigationDestination(
          for: TrendingPodcast.self,
          destination: { trendingPodcast in
            TrendingItemDetailView(
              viewModel: TrendingItemDetailViewModel(
                category: trendingPodcast.category,
                unsavedPodcast: trendingPodcast.unsavedPodcast
              )
            )
          }
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle("Trending")
  }
}

#Preview {
  @Previewable @State var viewModel: TrendingResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      TrendingResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    viewModel = TrendingResultsViewModel(
      category: "News",
      trendingResult: try! await PreviewHelpers.loadTrendingResult()
    )
  }
}
