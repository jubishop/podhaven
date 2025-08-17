// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct TitleSearchView: View {
  @State var viewModel: PodcastSearchViewModel

  var body: some View {
    VStack {
      switch viewModel.state {
      case .idle:
        VStack(spacing: 16) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 48))
            .foregroundColor(.secondary)
          Text("Search for podcasts by title")
            .font(.headline)
            .multilineTextAlignment(.center)
          Text("Enter podcast titles to find exact or similar podcast matches.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      case .loading:
        VStack {
          ProgressView("Searching...")
            .padding()
          Spacer()
        }

      case .loaded(let podcasts):
        if podcasts.isEmpty {
          VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 48))
              .foregroundColor(.secondary)
            Text("No results found")
              .font(.headline)
            Text("Try different search terms or check your spelling.")
              .font(.subheadline)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(podcasts, id: \.feedURL) { podcast in
            NavigationLink(
              value: Navigation.Search.Destination.searchedPodcast(
                SearchedPodcast(
                  searchedText: viewModel.searchText,
                  unsavedPodcast: podcast
                )
              ),
              label: {
                PodcastResultsListView(
                  podcast: podcast,
                  searchedText: viewModel.searchText
                )
              }
            )
          }
        }

      case .error(let message):
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 48))
            .foregroundColor(.red)
          Text("Search Error")
            .font(.headline)
          Text(message)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationTitle("Search by Title")
    .searchable(
      text: $viewModel.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search podcast titles..."
    )
  }
}

#if DEBUG
#Preview {
  let viewModel = PodcastSearchViewModel { searchText in
    let result = try await Container.shared.searchService().searchByTitle(searchText)
    return result.convertibleFeeds.compactMap {
      try? $0.toUnsavedPodcast()
    }
  }

  NavigationStack {
    TitleSearchView(viewModel: viewModel)
  }
  .preview()
}
#endif
