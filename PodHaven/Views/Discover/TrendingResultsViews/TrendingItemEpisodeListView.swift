// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemEpisodeListView: View {
  private let unsavedEpisode: UnsavedEpisode

  init(unsavedEpisode: UnsavedEpisode) {
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
    if let unsavedEpisodes = unsavedEpisodes {
      List {
        TrendingItemEpisodeListView(unsavedEpisode: unsavedEpisodes.randomElement()!)
      }
    }
  }
  .preview()
  .task {
    (unsavedPodcast, unsavedEpisodes) = try! await PreviewHelpers.loadUnsavedPodcastEpisodes()
  }
}
