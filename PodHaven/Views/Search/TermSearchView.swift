// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct TermSearchView: View {
  @State var viewModel: PodcastSearchViewModel

  var body: some View {
    VStack {
      switch viewModel.state {
      case .idle:
        VStack(spacing: 16) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 48))
            .foregroundColor(.secondary)
          Text("Search for podcasts by keyword")
            .font(.headline)
            .multilineTextAlignment(.center)
          Text(
            "Enter search terms to find podcasts that match keywords in their title, description, or content."
          )
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
    .navigationTitle("Search by Term")
    .searchable(
      text: $viewModel.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search podcasts..."
    )
  }
}

#if DEBUG
#Preview {
  let viewModel = PodcastSearchViewModel { searchText in
    let result = try await Container.shared.searchService().searchByTerm(searchText)
    return result.convertibleFeeds.compactMap {
      try? $0.toUnsavedPodcast()
    }
  }

  NavigationStack {
    TermSearchView(viewModel: viewModel)
  }
  .preview()
}
#endif
