// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct PodcastSearchView<ViewModel: PodcastSearchViewableModel>: View {
  @State var viewModel: ViewModel

  var body: some View {
    VStack {
      switch viewModel.state {
      case .idle:
        IdleStateView(
          title: viewModel.searchConfiguration.idleTitle,
          description: viewModel.searchConfiguration.idleDescription
        )

      case .loading:
        VStack {
          ProgressView("Searching...")
            .padding()
          Spacer()
        }

      case .loaded(let podcasts):
        if podcasts.isEmpty {
          EmptyResultsView()
        } else {
          PodcastResultsList(
            podcasts: podcasts,
            searchedText: viewModel.searchText
          )
        }

      case .error(let message):
        ErrorStateView(message: message)
      }
    }
    .navigationTitle(viewModel.searchConfiguration.navigationTitle)
    .searchable(
      text: $viewModel.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: viewModel.searchConfiguration.searchPrompt
    )
  }
}

// MARK: - Subviews

private struct IdleStateView: View {
  let title: String
  let description: String

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text(title)
        .font(.headline)
        .multilineTextAlignment(.center)
      Text(description)
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct EmptyResultsView: View {
  var body: some View {
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
  }
}

private struct ErrorStateView: View {
  let message: String

  var body: some View {
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

private struct PodcastResultsList: View {
  let podcasts: [UnsavedPodcast]
  let searchedText: String

  var body: some View {
    List(podcasts, id: \.feedURL) { podcast in
      NavigationLink(
        value: Navigation.Search.Destination.searchedPodcast(
          SearchedPodcast(
            searchedText: searchedText,
            unsavedPodcast: podcast
          )
        ),
        label: {
          PodcastResultsListView(
            podcast: podcast,
            searchedText: searchedText
          )
        }
      )
    }
  }
}

// MARK: - Previews

#if DEBUG
#Preview("Term Search") {
  NavigationStack {
    PodcastSearchView(viewModel: TermSearchViewModel())
  }
  .preview()
}

#Preview("Title Search") {
  NavigationStack {
    PodcastSearchView(viewModel: TitleSearchViewModel())
  }
  .preview()
}
#endif
