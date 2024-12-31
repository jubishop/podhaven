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
      if !PlayState.shared.isOnDeck(viewModel.podcastEpisode) {
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
              try await Repo.shared.unshiftToQueue(viewModel.episode.id)
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
