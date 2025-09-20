// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct EpisodesView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.episodes) {
      Form {
        NavigationLink(
          value: Navigation.Destination.episodesViewType(.recentEpisodes),
          label: { Text("Recent Episodes") }
        )
        NavigationLink(
          value: Navigation.Destination.episodesViewType(.unqueued),
          label: { Text("Unqueued") }
        )
        NavigationLink(
          value: Navigation.Destination.episodesViewType(.cached),
          label: { Text("Cached") }
        )
        NavigationLink(
          value: Navigation.Destination.episodesViewType(.finished),
          label: { Text("Finished") }
        )
        NavigationLink(
          value: Navigation.Destination.episodesViewType(.unfinished),
          label: { Text("Unfinished") }
        )
        NavigationLink(
          value: Navigation.Destination.episodesViewType(.previouslyQueued),
          label: { Text("Previously Queued") }
        )
      }
      .playBarSafeAreaInset()
      .navigationTitle("All Episode Lists")
    }
  }
}

#if DEBUG
#Preview {
  EpisodesView()
    .preview()
}
#endif
