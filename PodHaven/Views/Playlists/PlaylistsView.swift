// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct PlaylistsView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    NavigationStack(path: $navigation.playlistsPath) {
      Form {
        NavigationLink(
          value: Navigation.PlaylistsView.completed,
          label: { Text("Completed") }
        )
        NavigationLink(
          value: Navigation.PlaylistsView.unfinished,
          label: { Text("Unfinished") }
        )
      }
      .navigationTitle("All Playlists")
      .navigationDestination(
        for: Navigation.PlaylistsView.self,
        destination: navigation.standardPlaylistView
      )
    }
  }
}

#if DEBUG
#Preview {
  PlaylistsView()
    .preview()
}
#endif
