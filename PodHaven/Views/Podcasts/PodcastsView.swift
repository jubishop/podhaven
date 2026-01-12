// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct PodcastsView: View {
  @DynamicInjected(\.navigation) private var navigation

  var body: some View {
    NavStack(manager: navigation.podcasts) {
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
    }
  }
}

#if DEBUG
#Preview {
  PodcastsView()
    .preview()
}
#endif
