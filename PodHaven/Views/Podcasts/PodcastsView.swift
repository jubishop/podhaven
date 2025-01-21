// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct PodcastsView: View {
  @Environment(Alert.self) var alert

  @State private var navigation = Container.shared.navigation()
  @State private var viewModel = PodcastsViewModel()

  var body: some View {
    NavigationStack(path: $navigation.podcastsPath) {
      ScrollView {
        PodcastGrid(podcastSeries: viewModel.podcastSeries).padding()
      }
      .navigationTitle("Podcasts")
      .navigationDestination(for: PodcastSeries.self) { podcastSeries in
        SeriesView(viewModel: SeriesViewModel(podcastSeries: podcastSeries))
      }
      .navigationDestination(for: Podcast.self) { podcast in
        SeriesView(viewModel: SeriesViewModel(podcast: podcast))
      }
      .refreshable {
        do {
          try await viewModel.refreshPodcasts()
        } catch {
          alert.andReport("Failed to refresh all podcasts: \(error)")
        }
      }
    }
    .task {
      do {
        try await viewModel.observePodcasts()
      } catch {
        alert.andReport(error)
      }
    }
  }
}

#Preview {
  PodcastsView()
    .preview()
    .task {
      do {
        try await PreviewHelpers.importPodcasts()
      } catch { fatalError("Couldn't preview podcasts view: \(error)") }
    }
}
