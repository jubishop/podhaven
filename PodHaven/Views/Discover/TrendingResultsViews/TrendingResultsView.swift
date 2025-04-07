// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingResultsView: View {
  private let viewModel: ResultsViewModel

  init(viewModel: ResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      if viewModel.result != nil {
        List {
          ForEach(viewModel.unsavedPodcasts, id: \.feedURL) { unsavedPodcast in
            NavigationLink(
              value: SearchedPodcastByTrending(
                category: viewModel.searchText,
                unsavedPodcast: unsavedPodcast
              ),
              label: {
                SearchedPodcastByTrendingListView(unsavedPodcast: unsavedPodcast)
              }
            )
          }
        }
        .navigationDestination(
          for: SearchedPodcastByTrending.self,
          destination: { trendingPodcast in
            PodcastResultsView(
              viewModel: PodcastResultsViewModel(
                searchedPodcast: trendingPodcast
              )
            )
          }
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle("📈 \(viewModel.searchText)")
  }
}

#Preview {
  @Previewable @State var viewModel: ResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      TrendingResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let trendingResult = try! await PreviewHelpers.loadTrendingResult()
    viewModel = ResultsViewModel(
      searchResult: TrendingSearchResult(searchCategory: "News", trendingResult: trendingResult)
    )
  }
}
