// Copyright Justin Bishop, 2024

import SwiftUI

struct EpisodeView: View {
  @State private var viewModel: EpisodeViewModel

  init(episode: Episode) {
    _viewModel = State(initialValue: EpisodeViewModel(episode: episode))
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
    let episode: Episode
    init() {
      self.episode = try! PodcastRepository.shared.db.read { db in
        try! Episode.fetchOne(db)!
      }
    }

    var body: some View {
      EpisodeView(episode: episode)
    }
}

  return Preview { NavigationStack { EpisodeViewPreview() } }
}
