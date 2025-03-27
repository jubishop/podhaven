// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingResultsView: View {
  private let viewModel: TrendingResultsViewModel

  init(viewModel: TrendingResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      if viewModel.trendingResult != nil {
        List {
          ForEach(viewModel.unsavedPodcasts, id: \.feedURL) { unsavedPodcast in
            NavigationLink(
              value: TrendingPodcast(
                unsavedPodcast: unsavedPodcast,
                category: viewModel.category
              ),
              label: {
                TrendingPodcastListView(unsavedPodcast: unsavedPodcast)
              }
            )
          }
        }
        .navigationDestination(
          for: TrendingPodcast.self,
          destination: { trendingPodcast in
            TrendingPodcastView(
              viewModel: TrendingPodcastViewModel(
                trendingPodcast: trendingPodcast
              )
            )
          }
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle("📈 \(viewModel.category)")
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
    let trendingResult = try! await PreviewHelpers.loadTrendingResult()
    viewModel = TrendingResultsViewModel(
      searchResult: TrendingSearchResult(searchedCategory: "News", trendingResult: trendingResult)
    )
  }
}
