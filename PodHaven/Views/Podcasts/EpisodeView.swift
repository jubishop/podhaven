// Copyright Justin Bishop, 2024

import SwiftUI

struct EpisodeView: View {
  @State private var viewModel: EpisodeViewModel

  init(podcastEpisode: PodcastEpisode) {
    _viewModel = State(
      initialValue: EpisodeViewModel(podcastEpisode: podcastEpisode)
    )
  }

  var body: some View {
    VStack(spacing: 40) {
      Text(viewModel.podcast.toString)
      Text(viewModel.episode.toString)
      Text("Duration: \(viewModel.episode.duration.readable())")
      if !viewModel.onDeck {
        Button(
          action: viewModel.playNow,
          label: { Text("Play Now") }
        )
        Button(
          action: viewModel.addToTopOfQueue,
          label: { Text("Add To Top Of Queue") }
        )
        Button(
          action: viewModel.appendToQueue,
          label: { Text("Add To Bottom Of Queue") }
        )
      }
    }
    .task {
      await viewModel.observeEpisode()
    }
  }
}

#Preview {
  @Previewable @State var podcastEpisode: PodcastEpisode?

  Preview {
    NavigationStack {
      Group {
        if let podcastEpisode = podcastEpisode {
          EpisodeView(podcastEpisode: podcastEpisode)
        } else {
          Text("No episodes in DB")
        }
      }
    }
  }
  .task {
    podcastEpisode = try? await Helpers.loadPodcastEpisode()
  }
}
