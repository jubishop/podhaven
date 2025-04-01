// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchedPodcastByTrendingListView: View {
  private let unsavedPodcast: UnsavedPodcast

  init(unsavedPodcast: UnsavedPodcast) {
    self.unsavedPodcast = unsavedPodcast
  }

  var body: some View {
    Text(unsavedPodcast.title)
  }
}

#Preview {
  @Previewable @State var unsavedPodcast: UnsavedPodcast?

  NavigationStack {
    List {
      if let unsavedPodcast = unsavedPodcast {
        SearchedPodcastByTrendingListView(unsavedPodcast: unsavedPodcast)
      } else {
        Text("No trending result found")
      }
    }
  }
  .preview()
  .task {
    unsavedPodcast = try! await PreviewHelpers.loadUnsavedPodcast()
  }
}

