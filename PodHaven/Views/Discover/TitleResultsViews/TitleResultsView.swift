// Copyright Justin Bishop, 2025

import SwiftUI

struct TitleResultsView: View {
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
              value: SearchedPodcastByTitle(
                searchedText: viewModel.searchText,
                unsavedPodcast: unsavedPodcast
              ),
              label: {
                TitlePodcastListView(unsavedPodcast: unsavedPodcast)
              }
            )
          }
        }
        .navigationDestination(
          for: SearchedPodcastByTitle.self,
          destination: { titlePodcast in
            TitlePodcastView(
              viewModel: PodcastResultsViewModel(
                searchedPodcast: titlePodcast
              )
            )
          }
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle("🔍📖 \(viewModel.searchText)")
  }
}

#Preview {
  @Previewable @State var viewModel: ResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      TitleResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let titleResult = try! await PreviewHelpers.loadTitleResult()
    viewModel = ResultsViewModel(
      searchResult: TitleSearchResult(searchText: "Hello", titleResult: titleResult)
    )
  }
}
