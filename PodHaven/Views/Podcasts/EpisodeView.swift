// Copyright Justin Bishop, 2025

import SwiftUI

struct EpisodeView: View {
  @Environment(Alert.self) var alert

  private let viewModel: EpisodeViewModel

  init(viewModel: EpisodeViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 40) {
      Text(viewModel.podcast.toString)
        .font(.largeTitle)
      Text(viewModel.episode.toString)
      Text("Duration: \(viewModel.episode.duration.readable())")
      if !viewModel.onDeck {
        Button("Play Now") {
          viewModel.playNow()
        }
        Button("Add To Top Of Queue") {
          viewModel.addToTopOfQueue()
        }
        Button("Add To Bottom Of Queue") {
          viewModel.appendToQueue()
        }
      }
    }
    .navigationTitle(viewModel.episode.title)
    .task { await viewModel.execute() }
  }
}

#Preview {
  @Previewable @State var podcastEpisode: PodcastEpisode?

  NavigationStack {
    Group {
      if let podcastEpisode = podcastEpisode {
        EpisodeView(viewModel: EpisodeViewModel(podcastEpisode: podcastEpisode))
      } else {
        Text("No episodes in DB")
      }
    }
  }
  .preview()
  .task {
    podcastEpisode = try? await PreviewHelpers.loadPodcastEpisode()
  }
}
