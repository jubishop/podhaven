// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct PodcastsResultsView: View {
  @DynamicInjected(\.navigation) private var navigation

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
              value: SearchedPodcast(
                searchedText: viewModel.searchText,
                unsavedPodcast: unsavedPodcast
              ),
              label: {
                PodcastResultsListView(unsavedPodcast: unsavedPodcast)
              }
            )
          }
        }
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle(viewModel.title)
    .navigationDestination(
      for: SearchedPodcast.self,
      destination: navigation.podcastResultsDetailView
    )
  }
}

#if DEBUG
#Preview {
  @Previewable @State var viewModel: ResultsViewModel?

  NavigationStack {
    if let viewModel {
      PodcastsResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let termResult = try! await PreviewHelpers.loadTermResult()
    viewModel = ResultsViewModel(
      title: "🔍📖 Hard Fork",
      searchResult: PodcastSearchResult(searchText: "Hard Fork", result: termResult)
    )
  }
}
#endif
