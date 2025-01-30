// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemEpisodeDetailView: View {
  private let viewModel: TrendingItemEpisodeDetailViewModel

  init(viewModel: TrendingItemEpisodeDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    Text(viewModel.unsavedEpisode.title)
  }
}

#Preview {
  @Previewable @State var unsavedEpisodes: [UnsavedEpisode]?
  @Previewable @State var unsavedPodcast: UnsavedPodcast?

  NavigationStack {
    if let unsavedPodcast = unsavedPodcast, let unsavedEpisodes = unsavedEpisodes {
      List {
        TrendingItemEpisodeDetailView(
          viewModel: TrendingItemEpisodeDetailViewModel(
            unsavedPodcast: unsavedPodcast,
            unsavedEpisode: unsavedEpisodes.randomElement()!
          )
        )
      }
    }
  }
  .preview()
  .task {
    (unsavedPodcast, unsavedEpisodes) = try! await PreviewHelpers.loadUnsavedPodcastEpisodes()
  }
}
