// Copyright Justin Bishop, 2025

import Factory
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
              label: { PodcastGridItem(podcast: podcast) }
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
        let repo = Container.shared.repo()
        try await PreviewHelpers.importPodcasts(12)
        var allPodcasts = try await repo.allPodcasts().shuffled()
        allPodcasts[Int.random(in: 0...11)].image = URL(string: "http://nope.com/0.jpg")!
        podcasts = IdentifiedArray(uniqueElements: allPodcasts.prefix(12), id: \Podcast.feedURL)
      } catch { fatalError("Couldn't preview podcast grid: \(error)") }
    }
}
