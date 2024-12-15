// Copyright Justin Bishop, 2024

import GRDB
import NukeUI
import SwiftUI

struct PodcastsView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = PodcastsViewModel()

  var body: some View {
    NavigationStack(path: $navigation.podcastsPath) {
      ScrollView {
        ThumbnailGrid(podcasts: viewModel.podcasts).padding()
      }
      .navigationTitle("Podcasts")
      .navigationDestination(for: Podcast.self) { podcast in
        SeriesView(podcast: podcast)
      }
    }.task {
      await viewModel.observePodcasts()
    }
  }
}

#Preview {
  Preview { PodcastsView() }
}
