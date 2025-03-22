// Copyright Justin Bishop, 2025

import SwiftUI

struct AllFieldsPodcastListView: View {
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
        AllFieldsPodcastListView(unsavedPodcast: unsavedPodcast)
      } else {
        Text("No term search result found")
      }
    }
  }
  .preview()
  .task {
    unsavedPodcast = try! await PreviewHelpers.loadUnsavedPodcast()
  }
}
