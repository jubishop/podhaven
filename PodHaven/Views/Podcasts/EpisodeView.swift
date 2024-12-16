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
    Button(
      action: {
        Task { @PlayActor in
          do {
            try await PlayManager.shared.start(viewModel.podcastEpisode)
          } catch {
            await Alert.shared("Failed to start podcast: \(error)")
          }
        }
      },
      label: { Text(viewModel.episode.toString) }
    )
    .task {
      await viewModel.observeEpisode()
    }
  }
}

#Preview {
  struct EpisodeViewPreview: View {
    let podcastEpisode: PodcastEpisode
    init() {
      self.podcastEpisode = try! Repo.shared.db.read { db in
        try! Episode
          .including(required: Episode.podcast)
          .shuffled()
          .asRequest(of: PodcastEpisode.self)
          .fetchOne(db)!
      }
    }

    var body: some View {
      EpisodeView(podcastEpisode: podcastEpisode)
    }
  }

  return Preview { NavigationStack { EpisodeViewPreview() } }
}
