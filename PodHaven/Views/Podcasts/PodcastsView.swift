// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct PodcastsView: View {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.sharedState) private var sharedState

  @State private var viewModel = PodcastsViewModel()

  var body: some View {
    NavStack(manager: navigation.podcasts) {
      Form {
        Section("Standard") {
          NavigationLink(value: Navigation.Destination.podcastsViewType(.subscribed)) {
            LabeledContent("Subscribed") {
              Text("\(viewModel.counts?.subscribed ?? 0)")
                .foregroundStyle(.secondary)
            }
          }

          NavigationLink(value: Navigation.Destination.podcastsViewType(.unsubscribed)) {
            LabeledContent("Unsubscribed") {
              Text("\(viewModel.counts?.unsubscribed ?? 0)")
                .foregroundStyle(.secondary)
            }
          }
        }

        if !sharedState.tags.isEmpty {
          Section("Tags") {
            ForEach(sharedState.tags) { tag in
              NavigationLink(value: Navigation.Destination.podcastsViewType(.tag(tag.id))) {
                LabeledContent(tag.name) {
                  Text("\(viewModel.counts?.byTag[tag.id] ?? 0)")
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
      .navigationTitle("All Podcast Lists")
      .task(viewModel.execute)
    }
  }
}

#if DEBUG
#Preview {
  PodcastsView()
    .preview()
}
#endif
