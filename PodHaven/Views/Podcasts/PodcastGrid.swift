// Copyright Justin Bishop, 2025

import GRDB
import IdentifiedCollections
import SwiftUI

struct PodcastGrid: View {
  private let podcasts: PodcastArray
  private let numberOfColumns = 3

  init(podcasts: PodcastArray) {
    self.podcasts = podcasts
  }

  var body: some View {
    let rows = podcasts.chunked(size: numberOfColumns)
    Grid {
      ForEach(rows, id: \.self) { row in
        GridRow {
          ForEach(row) { podcast in
            NavigationLink(
              value: podcast,
              label: { PodcastThumbnail(podcast: podcast) }
            )
          }
        }
      }
    }
  }
}

#Preview {
  @Previewable @State var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  PodcastGrid(podcasts: podcasts)
    .preview()
    .task {
      do {
        try await PreviewHelpers.importPodcasts(12)

        var allPodcasts = try await Repo.shared.allPodcasts().shuffled()
        let shuffled = Array(0..<12).shuffled()
        allPodcasts[shuffled[0]].image = URL(string: "http://nope.com/0.jpg")!
        podcasts = IdentifiedArray(uniqueElements: allPodcasts.prefix(12), id: \Podcast.feedURL)
      } catch { fatalError("Couldn't preview podcast grid: \(error)") }
    }
}
