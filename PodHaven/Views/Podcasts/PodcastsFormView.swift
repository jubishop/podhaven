// Copyright Justin Bishop, 2025

import Factory
import GRDB
import SwiftUI

struct PodcastsFormView: View {
  @State private var navigation = Container.shared.navigation()

  var body: some View {
    NavigationStack(path: $navigation.podcastsPath) {
      Form {
        Section("Standard") {
          NavigationLink(value: Navigation.PodcastsView.all, label: { Text("All") })
          NavigationLink(value: Navigation.PodcastsView.subscribed, label: { Text("Subscribed") })
        }
      }
      .navigationTitle("All Lists")
      .navigationDestination(for: Navigation.PodcastsView.self) { list in
        switch list {
        case .all:
          PodcastsView(
            viewModel: PodcastsViewModel(
              navigationTitle: "All Podcasts"
            )
          )
        case .subscribed:
          PodcastsView(
            viewModel: PodcastsViewModel(
              navigationTitle: "Subscribed",
              podcastFilter: Schema.subscribedColumn == true
            )
          )
        }
      }
    }
  }
}

#Preview {
  PodcastsFormView()
    .preview()
}
