// Copyright Justin Bishop, 2025

import SwiftUI

struct EpisodeResultsDetailView: View {
  @Environment(Alert.self) var alert

  private let viewModel: EpisodeResultsDetailViewModel

  init(viewModel: EpisodeResultsDetailViewModel) {
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

#if DEBUG
#Preview {
  @Previewable @State var unsavedEpisodes: [UnsavedEpisode]?
  @Previewable @State var unsavedPodcast: UnsavedPodcast?

  NavigationStack {
    if let unsavedPodcast = unsavedPodcast, let unsavedEpisodes = unsavedEpisodes {
      EpisodeResultsDetailView(
        viewModel: EpisodeResultsDetailViewModel(
          searchedPodcastEpisode: SearchedPodcastEpisode(
            searchedText: "Bill Maher",
            unsavedPodcastEpisode: UnsavedPodcastEpisode(
              unsavedPodcast: unsavedPodcast,
              unsavedEpisode: unsavedEpisodes.randomElement()!
            )
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
#endif
