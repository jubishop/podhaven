// Copyright Justin Bishop, 2025

import SwiftUI

struct EpisodeSearchView: View {
  @State var viewModel: EpisodeSearchViewModel

  var body: some View {
    VStack(spacing: 0) {
      // Main content
      switch viewModel.state {
      case .idle:
        idleStateView

      case .loading:
        loadingStateView

      case .loaded(let unsavedPodcastEpisodes):
        if unsavedPodcastEpisodes.isEmpty {
          emptyResultsView
        } else {
          episodeResultsList(unsavedPodcastEpisodes)
        }

      case .error(let message):
        errorStateView(message: message)
      }
    }
    .navigationTitle("Search Episodes")
    .searchable(
      text: $viewModel.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Enter person's name..."
    )
  }

  var idleStateView: some View {
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

  var loadingStateView: some View {
    VStack {
      ProgressView("Searching...")
        .padding()
      Spacer()
    }
  }

  var emptyResultsView: some View {
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

  func episodeResultsList(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode]) -> some View {
    List(unsavedPodcastEpisodes) { unsavedPodcastEpisode in
      NavigationLink(
        value: Navigation.Search.Destination.searchedPodcastEpisode(
          SearchedPodcastEpisode(
            searchedText: viewModel.searchText,
            unsavedPodcastEpisode: unsavedPodcastEpisode
          )
        ),
        label: {
          EpisodeListView(
            viewModel: SelectableListItemModel(
              isSelected: .constant(false),
              item: unsavedPodcastEpisode,
              isSelecting: false
            )
          )
        }
      )
      .episodeListRow()
      .episodeSwipeActions(viewModel: viewModel, episode: unsavedPodcastEpisode)
      .episodeContextMenu(viewModel: viewModel, episode: unsavedPodcastEpisode)
    }
  }

  func errorStateView(message: String) -> some View {
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

// MARK: - Previews

#if DEBUG
#Preview("Episode Search") {
  NavigationStack {
    EpisodeSearchView(viewModel: EpisodeSearchViewModel())
  }
  .preview()
}
#endif
