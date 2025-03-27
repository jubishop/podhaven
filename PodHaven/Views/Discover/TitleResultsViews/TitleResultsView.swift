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
          destination: { titlePodcast in
            TitlePodcastView(
              viewModel: TitlePodcastViewModel(
                titlePodcast: titlePodcast
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
  @Previewable @State var viewModel: TitleResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      TitleResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let titleResult = try! await PreviewHelpers.loadTitleResult()
    viewModel = TitleResultsViewModel(
      searchResult: TitleSearchResult(searchedText: "Hello", titleResult: titleResult)
    )
  }
}
