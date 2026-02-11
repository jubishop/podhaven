// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct PodcastsView: View {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.sharedState) private var sharedState

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

        if !sharedState.tags.isEmpty {
          Section("Tags") {
            ForEach(sharedState.tags) { tag in
              NavigationLink(
                value: Navigation.Destination.podcastsViewType(.tag(tag.id)),
                label: { Text(tag.name) }
              )
            }
          }
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
