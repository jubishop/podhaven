// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemEpisodeDetailView: View {
  private let unsavedPodcast: UnsavedPodcast
  private let unsavedEpisode: UnsavedEpisode

  init(_ unsavedPodcast: UnsavedPodcast, _ unsavedEpisode: UnsavedEpisode) {
    self.unsavedPodcast = unsavedPodcast
    self.unsavedEpisode = unsavedEpisode
  }

  var body: some View {
    Text(unsavedEpisode.title)
  }
}

#Preview {
  @Previewable @State var unsavedEpisodes: [UnsavedEpisode]?
  @Previewable @State var unsavedPodcast: UnsavedPodcast?

  NavigationStack {
    if let unsavedPodcast = unsavedPodcast, let unsavedEpisodes = unsavedEpisodes {
      List {
        TrendingItemEpisodeDetailView(unsavedPodcast, unsavedEpisodes.randomElement()!)
      }
    }
  }
  .preview()
  .task {
    (unsavedPodcast, unsavedEpisodes) = try! await PreviewHelpers.loadUnsavedPodcastEpisodes()
  }
}
