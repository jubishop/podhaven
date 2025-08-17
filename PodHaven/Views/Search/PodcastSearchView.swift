// Copyright Justin Bishop, 2025

import SwiftUI

struct PodcastSearchView: View {
  @State var viewModel: PodcastSearchViewModel

  var body: some View {
    VStack(spacing: 0) {
      // Mode selection pills
      ModeSelectionView(selectedMode: $viewModel.selectedMode)
        .padding(.horizontal)
        .padding(.bottom, 8)

      // Main content
      switch viewModel.state {
      case .idle:
        IdleStateView(
          title: "Search for podcasts",
          description: viewModel.selectedMode.idleDescription
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
    .navigationTitle("Search Podcasts")
    .searchable(
      text: $viewModel.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: viewModel.selectedMode.searchPrompt
    )
  }
}

// MARK: - Mode Selection

private struct ModeSelectionView: View {
  @Binding var selectedMode: PodcastSearchViewModel.SearchMode

  var body: some View {
    HStack {
      ForEach(PodcastSearchViewModel.SearchMode.allCases, id: \.self) { mode in
        Button(action: {
          selectedMode = mode
        }) {
          Text(mode.displayName)
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 20)
                .fill(selectedMode == mode ? Color.accentColor : Color.secondary.opacity(0.2))
            )
            .foregroundColor(selectedMode == mode ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
      }
      Spacer()
    }
    .padding(.top, 8)
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
#Preview("Search Podcasts") {
  NavigationStack {
    PodcastSearchView(viewModel: PodcastSearchViewModel())
  }
  .preview()
}
#endif
