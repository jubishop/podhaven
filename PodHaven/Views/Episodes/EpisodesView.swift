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
          value: Navigation.Episodes.Destination.viewType(.completed),
          label: { Text("Completed") }
        )
        NavigationLink(
          value: Navigation.Episodes.Destination.viewType(.unfinished),
          label: { Text("Unfinished") }
        )
      }
      .navigationTitle("All Episode Lists")
      .navigationDestination(
        for: Navigation.Episodes.Destination.self
      ) { destination in
        navigation.episodes.navigationDestination(for: destination)
      }
    }
  }
}

#if DEBUG
#Preview {
  EpisodesView()
    .preview()
}
#endif
