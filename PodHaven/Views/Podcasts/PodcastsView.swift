// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct PodcastsView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    NavigationStack(path: $navigation.podcasts.path) {
      Form {
        Section("Standard") {
          NavigationLink(
            value: Navigation.Podcasts.Destination.viewType(.all),
            label: { Text("All") }
          )
          NavigationLink(
            value: Navigation.Podcasts.Destination.viewType(.subscribed),
            label: { Text("Subscribed") }
          )
          NavigationLink(
            value: Navigation.Podcasts.Destination.viewType(.unsubscribed),
            label: { Text("Unsubscribed") }
          )
        }
      }
      .navigationTitle("All Podcast Lists")
      .navigationDestination(
        for: Navigation.Podcasts.Destination.self
      ) { destination in
        navigation.podcasts.navigationDestination(for: destination)
      }
    }
  }
}

#if DEBUG
#Preview {
  PodcastsView()
    .preview()
}
#endif
