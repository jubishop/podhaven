// Copyright Justin Bishop, 2026

import SwiftUI

struct SearchDiscoveryListView: View {
  @State private var viewModel: SearchDiscoveryListViewModel

  init(viewModel: SearchDiscoveryListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    Group {
      if !viewModel.episodeList.filteredEntries.isEmpty {
        listView
      } else {
        switch viewModel.discoveryListState {
        case .empty:
          emptyPlaceholder
        // Picks exist but the projection into `episodeList` hasn't landed yet;
        // show progress instead of a blank list for that single hop.
        case .loading, .picks:
          loadingPlaceholder
        }
      }
    }
    .navigationTitle(viewModel.source.discoveryListTitle)
    .toolbar { selectableEpisodesToolbarItems(viewModel: viewModel) }
    .toolbarRole(.editor)
    .onChange(of: viewModel.discoveryListState, initial: true) { _, state in
      viewModel.syncEntries(for: state)
    }
  }

  // MARK: - List

  private var listView: some View {
    List(viewModel.episodeList.filteredEntries) { episode in
      NavigationLink(
        value: Navigation.Destination.listedEpisode(episode),
        label: {
          EpisodeListView(
            episode: episode,
            isSelecting: viewModel.episodeList.isSelecting,
            isSelected: $viewModel.episodeList.isSelected[episode.id]
          )
          .listRowSeparator()
        }
      )
      .listRow()
      .episodeSwipeActions(viewModel: viewModel, episode: episode)
      .episodeContextMenu(viewModel: viewModel, episode: episode)
    }
    .animation(.default, value: viewModel.episodeList.filteredEntries)
  }

  // MARK: - Placeholder

  private var loadingPlaceholder: some View {
    VStack(spacing: 16) {
      ProgressView()
      Text("Finding more top picks…")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyPlaceholder: some View {
    VStack(spacing: 16) {
      AppIcon.search.image
        .font(.system(size: 48))
      Text("No top picks left")
        .font(.headline)
      Text("You've worked through all the picks here.")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
