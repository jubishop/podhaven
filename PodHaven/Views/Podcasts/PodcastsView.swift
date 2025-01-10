// Copyright Justin Bishop, 2025

import SwiftUI

struct PodcastsView: View {
  @Environment(Alert.self) var alert
  @State private var navigation = Navigation.shared
  @State private var viewModel = PodcastsViewModel()

  var body: some View {
    NavigationStack(path: $navigation.podcastsPath) {
      ScrollView {
        PodcastGrid(podcasts: viewModel.podcasts).padding()
      }
      .navigationTitle("Podcasts")
      .navigationDestination(for: Podcast.self) { podcast in
        SeriesView(viewModel: SeriesViewModel(podcast: podcast))
      }
      .refreshable {
        try? await viewModel.refreshPodcasts()
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
