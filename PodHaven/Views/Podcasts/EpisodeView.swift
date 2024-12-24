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
            try await Repo.shared.insertToQueue(viewModel.episode.id, at: 1)
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
    .task {
      await viewModel.observeEpisode()
    }
  }
}

#Preview {
  struct EpisodeViewPreview: View {
    @State var podcastEpisode: PodcastEpisode?

    init() {
      podcastEpisode =
        try? Repo.shared.db.read { db in
          try Episode
            .including(required: Episode.podcast)
            .shuffled()
            .asRequest(of: PodcastEpisode.self)
            .fetchOne(db)
        }
    }

    var body: some View {
      Group {
        if let podcastEpisode = self.podcastEpisode {
          EpisodeView(podcastEpisode: podcastEpisode)
        } else {
          Text("No episodes in DB")
        }
      }
      .task {
        if self.podcastEpisode == nil {
          if let podcastSeries = try? await Helpers.loadSeries(),
            let episode = podcastSeries.episodes.randomElement()
          {
            self.podcastEpisode = PodcastEpisode(
              podcast: podcastSeries.podcast,
              episode: episode
            )
          }
        }
      }
    }
  }

  return Preview { NavigationStack { EpisodeViewPreview() } }
}
