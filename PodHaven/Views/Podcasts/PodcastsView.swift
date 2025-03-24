// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct PodcastsView: View {
  @Environment(Alert.self) var alert

  private let viewModel: PodcastsViewModel

  init(viewModel: PodcastsViewModel = PodcastsViewModel()) {
    self.viewModel = viewModel
  }

  var body: some View {
    ScrollView {
      PodcastGrid(podcasts: viewModel.podcasts) { podcast in
        NavigationLink(
          value: podcast,
          label: { PodcastGridItem(podcast: podcast) }
        )
      }
      .padding()
    }
    .navigationTitle("Podcast List")
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
    .task { await viewModel.execute() }
  }
}

#Preview {
  NavigationStack {
    PodcastsView()
  }
  .preview()
  .task {
    try! await PreviewHelpers.importPodcasts()
  }
}
