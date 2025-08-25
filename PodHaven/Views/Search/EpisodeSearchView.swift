// Copyright Justin Bishop, 2025

import SwiftUI

struct EpisodeSearchView: View {
  @State var viewModel: EpisodeSearchViewModel

  var body: some View {
    VStack(spacing: 0) {
      // Main content
      switch viewModel.state {
      case .idle:
        IdleStateView()

      case .loading:
        VStack {
          ProgressView("Searching...")
            .padding()
          Spacer()
        }

      case .loaded(let episodes):
        if episodes.isEmpty {
          EmptyResultsView()
        } else {
          EpisodeResultsList(
            episodes: episodes,
            searchedText: viewModel.searchText
          )
        }

      case .error(let message):
        ErrorStateView(message: message)
      }
    }
    .navigationTitle("Search Episodes")
    .searchable(
      text: $viewModel.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Enter person's name..."
    )
  }
}

// MARK: - Subviews

private struct IdleStateView: View {
  var body: some View {
    VStack(spacing: 16) {
      AppLabel.personSearch.image
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("Search for episodes")
        .font(.headline)
        .multilineTextAlignment(.center)
      Text("Enter a person's name to find episodes they appear in.")
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
      AppLabel.noPersonFound.image
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("No episodes found")
        .font(.headline)
      Text("Try a different person's name or check your spelling.")
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
      AppLabel.error.image
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

private struct EpisodeResultsList: View {
  let episodes: [UnsavedPodcastEpisode]
  let searchedText: String

  var body: some View {
    List(episodes, id: \.id) { episode in
      NavigationLink(
        value: Navigation.Search.Destination.searchedPodcastEpisode(
          SearchedPodcastEpisode(
            searchedText: searchedText,
            unsavedPodcastEpisode: episode
          )
        ),
        label: {
          PodcastEpisodeListView(
            viewModel: SelectableListItemModel(
              isSelected: .constant(false),
              item: episode,
              isSelecting: false
            )
          )
        }
      )
    }
  }
}

// MARK: - Previews

#if DEBUG
#Preview("Episode Search") {
  NavigationStack {
    EpisodeSearchView(viewModel: EpisodeSearchViewModel())
  }
  .preview()
}
#endif
