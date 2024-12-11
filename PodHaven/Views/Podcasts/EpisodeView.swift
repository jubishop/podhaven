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
        if let media = viewModel.episode.media {
          Task.detached(priority: .userInitiated) {
            await PlayManager.shared.start(media)
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
      self.podcastEpisode = try! PodcastRepository.shared.db.read { db in
        try! Episode
          .including(required: Episode.podcast)
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
