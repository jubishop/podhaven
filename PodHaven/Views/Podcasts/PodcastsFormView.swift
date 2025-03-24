// Copyright Justin Bishop, 2025

import Factory
import GRDB
import SwiftUI

struct PodcastsFormView: View {
  enum Lists {
    case all
    case subscribed
  }

  @State private var navigation = Container.shared.navigation()

  var body: some View {
    NavigationStack(path: $navigation.podcastsPath) {
      Form {
        Section("Standard") {
          NavigationLink(value: Lists.all, label: { Text("All") })
          NavigationLink(value: Lists.subscribed, label: { Text("Subscribed") })
        }
      }
      .navigationTitle("All Lists")
      .navigationDestination(for: Lists.self) { list in
        switch list {
        case .all: PodcastsView()
        case .subscribed:
          PodcastsView(
            viewModel: PodcastsViewModel(podcastFilter: Schema.subscribedColumn == true)
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
