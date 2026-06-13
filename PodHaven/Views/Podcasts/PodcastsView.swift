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
          row("Subscribed", counts?.subscribed ?? 0, .subscribed)
          row("Unsubscribed", counts?.unsubscribed ?? 0, .unsubscribed)
        }

        if !cadenceRows.isEmpty {
          Section("Freshness") {
            ForEach(cadenceRows, id: \.self) { cadence in
              row(
                cadence.displayName,
                counts?.byFreshnessCadence[cadence] ?? 0,
                .freshnessCadence(cadence)
              )
            }
          }
        }

        if (counts?.queueOnTop ?? 0) > 0 || (counts?.queueOnBottom ?? 0) > 0 {
          Section("Queue") {
            if let count = counts?.queueOnTop, count > 0 {
              row("On Top", count, .queueOnTop)
            }
            if let count = counts?.queueOnBottom, count > 0 {
              row("On Bottom", count, .queueOnBottom)
            }
          }
        }

        if (counts?.autoCache ?? 0) > 0 || (counts?.autoSave ?? 0) > 0 {
          Section("Storage") {
            if let count = counts?.autoCache, count > 0 {
              row("Cache", count, .autoCache)
            }
            if let count = counts?.autoSave, count > 0 {
              row("Save", count, .autoSave)
            }
          }
        }

        if let count = counts?.notifyNewEpisodes, count > 0 {
          Section("Notifications") {
            row("Notify New Episodes", count, .notifyNewEpisodes)
          }
        }

        if !sharedState.tags.isEmpty {
          Section("Tags") {
            row("Untagged", counts?.untagged ?? 0, .untagged)
            ForEach(sharedState.tags) { tag in
              row(tag.name, counts?.byTag[tag.id] ?? 0, .tag(tag.id))
            }
          }
        }
      }
      .navigationTitle("Podcasts")
      .task(viewModel.execute)
    }
  }

  private var counts: PodcastCounts? { viewModel.counts }

  private var cadenceRows: [FreshnessCadence] {
    FreshnessCadence.allCases.filter { (counts?.byFreshnessCadence[$0] ?? 0) > 0 }
  }

  @ViewBuilder
  private func row(
    _ title: String,
    _ count: Int,
    _ viewType: Navigation.PodcastsViewType
  ) -> some View {
    NavigationLink(value: Navigation.Destination.podcastsViewType(viewType)) {
      LabeledContent(title) {
        Text("\(count)")
          .foregroundStyle(.secondary)
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
