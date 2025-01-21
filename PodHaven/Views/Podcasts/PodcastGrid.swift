// Copyright Justin Bishop, 2025

import Factory
import GRDB
import IdentifiedCollections
import SwiftUI

struct PodcastGrid: View {
  private let podcasts: [Podcast]
  private let numberOfColumns = 3

  init(podcasts: [Podcast]) {
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
  @Previewable @State var podcasts: [Podcast] = []

  PodcastGrid(podcasts: podcasts)
    .preview()
    .task {
      do {
        let repo = Container.shared.repo()
        try await PreviewHelpers.importPodcasts(12)
        var allPodcasts = try await repo.allPodcasts().shuffled()
        allPodcasts[Int.random(in: 0...11)].image = URL(string: "http://nope.com/0.jpg")!
        podcasts = Array(allPodcasts.prefix(12))
      } catch { fatalError("Couldn't preview podcast grid: \(error)") }
    }
}
