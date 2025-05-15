// Copyright Justin Bishop, 2025

import FactoryKit
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
        NavigationLink(
          value: Navigation.PlaylistsView.unfinished,
          label: { Text("Unfinished") }
        )
      }
      .navigationTitle("All Playlists")
      .navigationDestination(for: Navigation.PlaylistsView.self) { list in
        switch list {
        case .completed:
          StandardPlaylistView(
            viewModel: StandardPlaylistViewModel(
              title: "Completed",
              filter: Episode.completed,
              order: Episode.Columns.completionDate.desc
            )
          )
        case .unfinished:
          StandardPlaylistView(
            viewModel: StandardPlaylistViewModel(
              title: "Unfinished",
              filter: Episode.started && Episode.uncompleted
            )
          )
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
