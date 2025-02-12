// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemEpisodeDetailView: View {
  @Environment(Alert.self) var alert

  @State private var viewModel: TrendingItemEpisodeDetailViewModel

  init(viewModel: TrendingItemEpisodeDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      Text(viewModel.unsavedEpisode.title)
      Text("Duration: \(viewModel.unsavedEpisode.duration.readable())")
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
