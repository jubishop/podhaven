// Copyright Justin Bishop, 2025

import Factory
import GRDB
import SwiftUI

struct PlaylistsView: View {
  @State private var navigation = Container.shared.navigation()

  var body: some View {
    NavigationStack(path: $navigation.playlistsPath) {
      Form {
        NavigationLink(
          value: Navigation.PlaylistsView.completed,
          label: { Text("Completed") }
        )
      }
      .navigationTitle("All Playlists")
      .navigationDestination(for: Navigation.PlaylistsView.self) { list in
        switch list {
        case .completed:
          CompletedView()
        }
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
