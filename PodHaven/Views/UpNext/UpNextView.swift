// Copyright Justin Bishop, 2024

import SwiftUI

struct UpNextView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = UpNextViewModel()

  var body: some View {
    NavigationStack(path: $navigation.upNextPath) {
      List {
        ForEach(viewModel.podcastEpisodes) { podcastEpisode in
          UpNextListView(podcastEpisode: podcastEpisode)
        }
      }
      .navigationTitle("Up Next")
      .navigationDestination(for: PodcastEpisode.self) { podcastEpisode in
        EpisodeView(podcastEpisode: podcastEpisode)
      }
      .task {
        await viewModel.observePodcastEpisodes()
      }
    }
  }
}

#Preview {
  Preview { UpNextView() }
}
