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

      case .loaded:
        if viewModel.episodes.isEmpty {
          emptyResultsView
        } else {
          episodeResultsList
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
    .onDisappear { viewModel.disappear() }
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

  var episodeResultsList: some View {
    List(viewModel.episodes, id: \.mediaGUID) { episode in
      NavigationLink(
        value: Navigation.Destination.episode(DisplayedEpisode(episode)),
        label: {
          EpisodeListView(
            episode: episode
          )
        }
      )
      .episodeListRow()
      .episodeSwipeActions(viewModel: viewModel, episode: episode)
      .episodeContextMenu(viewModel: viewModel, episode: episode) {
        if let podcastEpisode = episode as? PodcastEpisode {
          Button(
            action: { viewModel.showPodcast(podcastEpisode) },
            label: { AppLabel.showPodcast.label }
          )
        }
      }
    }
    .playBarSafeAreaInset()
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
