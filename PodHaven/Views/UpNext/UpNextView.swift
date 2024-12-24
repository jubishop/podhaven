// Copyright Justin Bishop, 2024

import SwiftUI

struct UpNextView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = UpNextViewModel()

  var body: some View {
    NavigationStack(path: $navigation.upNextPath) {
      List {
        ForEach(viewModel.podcastEpisodes) { podcastEpisode in
          Text(podcastEpisode.episode.title ?? podcastEpisode.podcast.title)
        }
      }
      .navigationTitle("Up Next")
      .navigationDestination(for: Episode.self) { episode in
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
