// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct PlaylistsView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    NavigationStack(path: $navigation.playlists.path) {
      Form {
        NavigationLink(
          value: Navigation.Playlists.Destination.viewType(.completed),
          label: { Text("Completed") }
        )
        NavigationLink(
          value: Navigation.Playlists.Destination.viewType(.unfinished),
          label: { Text("Unfinished") }
        )
      }
      .navigationTitle("All Playlists")
      .navigationDestination(
        for: Navigation.Playlists.Destination.self
      ) { destination in
        navigation.playlists.navigationDestination(for: destination)
      }
    }
  }
}

#if DEBUG
#Preview {
  PlaylistsView()
    .preview()
}
#endif
