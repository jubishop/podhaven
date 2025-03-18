// Copyright Justin Bishop, 2025

import SwiftUI

struct TitleResultsView: View {
  private let viewModel: TitleResultsViewModel

  init(viewModel: TitleResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      if viewModel.titleResult != nil {
        List {
          ForEach(viewModel.unsavedPodcasts, id: \.feedURL) { unsavedPodcast in
            NavigationLink(
              value: SearchedPodcastByTitle(
                unsavedPodcast: unsavedPodcast,
                searchText: viewModel.searchText
              ),
              label: {
                TitlePodcastListView(unsavedPodcast: unsavedPodcast)
              }
            )
          }
        }
        .navigationDestination(
          for: SearchedPodcastByTitle.self,
          destination: { searchedPodcast in
            Text("Hello")
          }
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle("🔍🎙 \(viewModel.searchText)")
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
