// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI

struct SearchDiscoveryListView: View {
  @DynamicInjected(\.navigation) private var navigation

  private let source: SearchRecommendationCollector.Source
  private let actionsViewModel: SearchDiscoveryActionsViewModel

  init(
    source: SearchRecommendationCollector.Source,
    actionsViewModel: SearchDiscoveryActionsViewModel
  ) {
    self.source = source
    self.actionsViewModel = actionsViewModel
  }

  var body: some View {
    let picks = actionsViewModel.collector.picks(for: source)
    Group {
      if picks.isEmpty {
        emptyPlaceholder
      } else {
        listView(picks: picks)
      }
    }
    .navigationTitle(source.discoveryListTitle)
    .toolbarRole(.editor)
  }

  // MARK: - List

  private func listView(
    picks: [SearchRecommendationCollector.ScoredEpisode]
  ) -> some View {
    List(picks) { pick in
      let listed = ListedEpisode(pick.episode)
      NavigationLink(
        value: Navigation.Destination.listedEpisode(listed),
        label: {
          EpisodeListView(episode: listed)
            .listRowSeparator()
        }
      )
      .listRow()
      .episodeSwipeActions(viewModel: actionsViewModel, episode: listed)
      .episodeContextMenu(viewModel: actionsViewModel, episode: listed)
    }
    .animation(.default, value: picks)
  }

  // MARK: - Placeholder

  private var emptyPlaceholder: some View {
    VStack(spacing: 16) {
      AppIcon.search.image
        .font(.system(size: 48))
      Text("No top picks yet")
        .font(.headline)
      Text("Tap a result to dive deeper, then check back here.")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
