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
        Task.detached(priority: .userInitiated) {
          // TODO: Do something smart if this throws
          try await PlayManager.shared.start(viewModel.podcastEpisode)
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
      self.podcastEpisode = try! PodcastRepository.shared.db.read { db in
        try! Episode
          .including(required: Episode.podcast)
          .order(sql: "RANDOM()")
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
