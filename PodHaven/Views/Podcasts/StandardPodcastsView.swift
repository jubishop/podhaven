// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct StandardPodcastsView: View {
  @Environment(Alert.self) var alert

  @State private var viewModel: StandardPodcastsViewModel

  init(viewModel: StandardPodcastsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    SearchBar(
      text: $viewModel.podcastList.entryFilter,
      placeholder: "Filter podcasts",
      imageName: "line.horizontal.3.decrease.circle"
    )

    ScrollView {
      PodcastGrid(podcasts: viewModel.podcastList.filteredEntries) { podcast in
        NavigationLink(
          value: podcast,
          label: { PodcastGridItem(podcast: podcast) }
        )
      }
      .padding()
    }
    .navigationTitle(viewModel.title)
    .navigationDestination(for: Podcast.self) { podcast in
      PodcastView(viewModel: PodcastViewModel(podcast: podcast))
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
