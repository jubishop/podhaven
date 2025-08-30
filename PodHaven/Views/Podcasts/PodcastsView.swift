// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct PodcastsView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.podcasts) {
      Form {
        Section("Standard") {
          NavigationLink(
            value: Navigation.Destination.podcastsViewType(.subscribed),
            label: { Text("Subscribed") }
          )
          NavigationLink(
            value: Navigation.Destination.podcastsViewType(.unsubscribed),
            label: { Text("Unsubscribed") }
          )
        }
      }
      .navigationTitle("All Podcast Lists")
      .navigationDestination(
        for: Navigation.Destination.self,
        destination: navigation.navigationDestination
      )
    }
  }
}

#if DEBUG
#Preview {
  PodcastsView()
    .preview()
}
#endif
