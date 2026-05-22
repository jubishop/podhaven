// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI

struct SearchDiscoveryListView: View {
  @DynamicInjected(\.navigation) private var navigation
  @Environment(SearchRecommendationCollector.self) private var collector

  private let source: SearchRecommendationCollector.Source

  init(source: SearchRecommendationCollector.Source) {
    self.source = source
  }

  var body: some View {
    let picks = collector.picks(for: source)
    Group {
      if picks.isEmpty {
        emptyPlaceholder
      } else {
        listView(picks: picks, collector: collector)
      }
    }
    .navigationTitle(source.discoveryListTitle)
    .toolbarRole(.editor)
  }

  // MARK: - List

  private func listView(
    picks: [SearchRecommendationCollector.ScoredEpisode],
    collector: SearchRecommendationCollector
  ) -> some View {
    let viewModel = SearchDiscoveryActionsViewModel(collector: collector)
    return List(picks) { pick in
      let listed = ListedEpisode(pick.episode)
      NavigationLink(
        value: Navigation.Destination.listedEpisode(listed),
        label: {
          EpisodeListView(episode: listed)
            .listRowSeparator()
        }
      )
      .listRow()
      .episodeSwipeActions(viewModel: viewModel, episode: listed)
      .episodeContextMenu(viewModel: viewModel, episode: listed)
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
