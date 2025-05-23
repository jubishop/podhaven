// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct EpisodeDetailView: View {
  @DynamicInjected(\.alert) private var alert

  private let viewModel: EpisodeDetailViewModel

  init(viewModel: EpisodeDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 40) {
      Text(viewModel.podcast.toString)
        .font(.largeTitle)
      Text(viewModel.episode.toString)
      Text("Duration: \(viewModel.episode.duration)")
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
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var podcastEpisode: PodcastEpisode?

  NavigationStack {
    Group {
      if let podcastEpisode = podcastEpisode {
        EpisodeDetailView(viewModel: EpisodeDetailViewModel(podcastEpisode: podcastEpisode))
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
#endif
