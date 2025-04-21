// Copyright Justin Bishop, 2025

import SwiftUI

struct PodcastListResultsView: View {
  private let unsavedPodcast: UnsavedPodcast

  init(unsavedPodcast: UnsavedPodcast) {
    self.unsavedPodcast = unsavedPodcast
  }

  var body: some View {
    Text(unsavedPodcast.title)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var unsavedPodcast: UnsavedPodcast?

  NavigationStack {
    List {
      if let unsavedPodcast = unsavedPodcast {
        PodcastListResultsView(unsavedPodcast: unsavedPodcast)
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
#endif

