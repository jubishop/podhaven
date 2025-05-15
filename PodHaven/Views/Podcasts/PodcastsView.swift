// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct PodcastsView: View {
  @State private var navigation = Container.shared.navigation()

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
      .navigationDestination(for: Navigation.PodcastsView.self) { list in
        switch list {
        case .all:
          StandardPodcastsView(
            viewModel: StandardPodcastsViewModel(
              title: "All Podcasts"
            )
          )
        case .subscribed:
          StandardPodcastsView(
            viewModel: StandardPodcastsViewModel(
              title: "Subscribed",
              filter: Podcast.subscribed
            )
          )
        case .unsubscribed:
          StandardPodcastsView(
            viewModel: StandardPodcastsViewModel(
              title: "Unsubscribed",
              filter: Podcast.unsubscribed
            )
          )
        }
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
