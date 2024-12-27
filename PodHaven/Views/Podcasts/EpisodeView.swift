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
      Text(viewModel.episode.toString)
      Text("Duration: \(String(describing: viewModel.episode.duration))")
      if !viewModel.currentlyPlaying() {
        Button(
          action: {
            Task { @PlayActor in
              await PlayManager.shared.load(viewModel.podcastEpisode)
              PlayManager.shared.play()
            }
          },
          label: { Text("Play Now") }
        )
        Button(
          action: {
            Task {
              try await Repo.shared.insertToQueue(viewModel.episode.id, at: 0)
            }
          },
          label: { Text("Add To Top Of Queue") }
        )
        Button(
          action: {
            Task {
              try await Repo.shared.appendToQueue(viewModel.episode.id)
            }
          },
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
  struct EpisodeViewPreview: View {
    @State var podcastEpisode: PodcastEpisode?

    var body: some View {
      Group {
        if let podcastEpisode = self.podcastEpisode {
          EpisodeView(podcastEpisode: podcastEpisode)
        } else {
          Text("No episodes in DB")
        }
      }
      .task {
        self.podcastEpisode = try? await Helpers.loadPodcastEpisode()
      }
    }
  }

  return Preview { NavigationStack { EpisodeViewPreview() } }
}
