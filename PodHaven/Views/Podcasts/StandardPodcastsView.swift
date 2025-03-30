// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct StandardPodcastsView: View {
  @Environment(Alert.self) var alert

  private let viewModel: StandardPodcastsViewModel

  init(viewModel: StandardPodcastsViewModel) {
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
    .navigationTitle(viewModel.title)
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
    StandardPodcastsView(viewModel: StandardPodcastsViewModel(title: "Preview Podcasts"))
  }
  .preview()
  .task {
    try! await PreviewHelpers.importPodcasts()
  }
}
