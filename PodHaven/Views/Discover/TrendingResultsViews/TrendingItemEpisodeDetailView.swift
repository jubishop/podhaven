// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemEpisodeDetailView: View {
  @Environment(Alert.self) var alert

  private let viewModel: TrendingItemEpisodeDetailViewModel

  init(viewModel: TrendingItemEpisodeDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      Text(viewModel.unsavedEpisode.title)
      Text("Duration: \(viewModel.unsavedEpisode.duration.readable())")
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
    .navigationTitle(viewModel.unsavedEpisode.title)
    .task { await viewModel.execute() }
  }
}

#Preview {
  @Previewable @State var unsavedEpisodes: [UnsavedEpisode]?
  @Previewable @State var unsavedPodcast: UnsavedPodcast?

  NavigationStack {
    if let unsavedPodcast = unsavedPodcast, let unsavedEpisodes = unsavedEpisodes {
      TrendingItemEpisodeDetailView(
        viewModel: TrendingItemEpisodeDetailViewModel(
          unsavedPodcastEpisode: UnsavedPodcastEpisode(
            unsavedPodcast: unsavedPodcast,
            unsavedEpisode: unsavedEpisodes.randomElement()!
          )
        )
      )
    }
  }
  .preview()
  .task {
    (unsavedPodcast, unsavedEpisodes) = try! await PreviewHelpers.loadUnsavedPodcastEpisodes()
  }
}
