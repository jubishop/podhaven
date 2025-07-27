// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct EpisodesView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    NavigationStack(path: $navigation.episodes.path) {
      Form {
        NavigationLink(
          value: Navigation.Episodes.Destination.viewType(.recentEpisodes),
          label: { Text("Recent Episodes") }
        )
        NavigationLink(
          value: Navigation.Episodes.Destination.viewType(.completed),
          label: { Text("Completed") }
        )
        NavigationLink(
          value: Navigation.Episodes.Destination.viewType(.unfinished),
          label: { Text("Unfinished") }
        )
        NavigationLink(
          value: Navigation.Episodes.Destination.viewType(.previouslyQueued),
          label: { Text("Previously Queued") }
        )
      }
      .navigationTitle("All Episode Lists")
      .navigationDestination(
        for: Navigation.Episodes.Destination.self,
        destination: navigation.episodes.navigationDestination
      )
    }
  }
}

#if DEBUG
#Preview {
  EpisodesView()
    .preview()
}
#endif
