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
        for: Navigation.Podcasts.Destination.self,
        destination: navigation.podcasts.navigationDestination
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
