// Copyright Justin Bishop, 2025

import SwiftUI

struct PodcastSearchView: View {
  @State var viewModel: PodcastSearchViewModel

  var body: some View {
    VStack(spacing: 0) {
      // Mode selection pills
      modeSelectionView
        .padding(.horizontal)
        .padding(.bottom, 8)

      // Main content
      switch viewModel.state {
      case .idle:
        idleStateView

      case .loading:
        loadingStateView

      case .loaded:
        if viewModel.podcasts.isEmpty {
          emptyResultsView
        } else {
          podcastResultsList
        }

      case .error(let message):
        errorStateView(message: message)
      }
    }
    .navigationTitle("Search Podcasts")
    .searchable(
      text: $viewModel.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: viewModel.selectedMode.searchPrompt
    )
    .onDisappear { viewModel.disappear() }
  }

  // MARK: - Computed View Properties

  var modeSelectionView: some View {
    HStack {
      ForEach(PodcastSearchViewModel.SearchMode.allCases, id: \.self) { mode in
        Button(action: {
          viewModel.selectedMode = mode
        }) {
          Text(mode.displayName)
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 20)
                .fill(
                  viewModel.selectedMode == mode ? Color.accentColor : Color.secondary.opacity(0.2)
                )
            )
            .foregroundColor(viewModel.selectedMode == mode ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
      }
      Spacer()
    }
    .padding(.top, 8)
  }

  var idleStateView: some View {
    VStack(spacing: 16) {
      AppLabel.search.image
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("Search for podcasts")
        .font(.headline)
        .multilineTextAlignment(.center)
      Text(viewModel.selectedMode.idleDescription)
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
      AppLabel.search.image
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

  var podcastResultsList: some View {
    List(viewModel.podcasts, id: \.feedURL) { podcast in
      NavigationLink(
        value: Navigation.Destination.podcast(DisplayedPodcast(podcast)),
        label: {
          PodcastListView(podcast: podcast)
        }
      )
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
#Preview("Search Podcasts") {
  NavigationStack {
    PodcastSearchView(viewModel: PodcastSearchViewModel())
  }
  .preview()
}
#endif
