// Copyright Justin Bishop, 2025

import SwiftUI

struct EpisodeView: View {
  @Environment(Alert.self) var alert
  @State private var viewModel: EpisodeViewModel

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
      do {
        try await viewModel.observeEpisode()
      } catch {
        alert.andReport(error)
      }
    }
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
