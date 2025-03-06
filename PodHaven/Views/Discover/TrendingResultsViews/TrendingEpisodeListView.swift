// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingEpisodeListView: View {
  private let unsavedEpisode: UnsavedEpisode

  init(unsavedEpisode: UnsavedEpisode) {
    self.unsavedEpisode = unsavedEpisode
  }

  var body: some View {
    Text(unsavedEpisode.title)
  }
}

#Preview {
  @Previewable @State var unsavedEpisode: UnsavedEpisode?

  NavigationStack {
    if let unsavedEpisode = unsavedEpisode {
      List {
        TrendingEpisodeListView(unsavedEpisode: unsavedEpisode)
      }
    }
  }
  .preview()
  .task {
    unsavedEpisode = try! await PreviewHelpers.loadUnsavedEpisode()
  }
}
