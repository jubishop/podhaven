// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct PodcastsView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    NavigationStack(path: $navigation.podcastsPath) {
      Form {
        Section("Standard") {
          NavigationLink(
            value: Navigation.PodcastsView.all,
            label: { Text("All") }
          )
          NavigationLink(
            value: Navigation.PodcastsView.subscribed,
            label: { Text("Subscribed") }
          )
          NavigationLink(
            value: Navigation.PodcastsView.unsubscribed,
            label: { Text("Unsubscribed") }
          )
        }
      }
      .navigationTitle("All Podcast Lists")
      .navigationDestination(
        for: Navigation.PodcastsView.self,
        destination: navigation.standardPodcastsView
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
