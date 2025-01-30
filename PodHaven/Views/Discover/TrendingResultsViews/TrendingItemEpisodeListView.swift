// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemEpisodeListView: View {
  private let unsavedEpisode: UnsavedEpisode

  init(unsavedEpisode: UnsavedEpisode) {
    self.unsavedEpisode= unsavedEpisode
  }

  var body: some View {
    NavigationLink(
      value: unsavedEpisode
      label: { Text(unsavedEpisodetitle) }
    )
  }
}

#Preview {
  @Previewable @State var unsavedEpisode TrendingResult.FeedResult?

  NavigationStack {
    List {
      if let unsavedEpisode= unsavedEpisode{
        TrendingItemListView(uunsavedEpisode
      } else {
        Text("No trending result found")
      }
    }
  }
  .preview()
  .task {
    unsavedEpisode= try! await PreviewHelpers.loadFeedResult()
  }
}

