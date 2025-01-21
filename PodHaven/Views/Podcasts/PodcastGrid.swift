// Copyright Justin Bishop, 2025

import Factory
import GRDB
import IdentifiedCollections
import SwiftUI

struct PodcastGrid: View {
  private let podcastSeries: PodcastSeriesArray
  private let numberOfColumns = 3

  init(podcastSeries: PodcastSeriesArray) {
    self.podcastSeries = podcastSeries
  }

  var body: some View {
    let rows = podcastSeries.chunked(size: numberOfColumns)
    Grid {
      ForEach(rows, id: \.self) { row in
        GridRow {
          ForEach(row) { podcastSeries in
            NavigationLink(
              value: podcastSeries,
              label: { PodcastGridItem(podcast: podcastSeries.podcast) }
            )
          }
        }
      }
    }
  }
}

#Preview {
  @Previewable @State var podcastSeries: PodcastSeriesArray = IdentifiedArray(
    id: \PodcastSeries.podcast.feedURL
  )

  PodcastGrid(podcastSeries: podcastSeries)
    .preview()
    .task {
      do {
        let repo = Container.shared.repo()
        try await PreviewHelpers.importPodcasts(12)
        var allPodcasts = try await repo.allPodcasts().shuffled()
        allPodcasts[Int.random(in: 0...11)].image = URL(string: "http://nope.com/0.jpg")!
        podcastSeries = IdentifiedArray(
          uniqueElements: Array(allPodcasts.prefix(12)).map { PodcastSeries(podcast: $0) },
          id: \PodcastSeries.podcast.feedURL
        )
      } catch { fatalError("Couldn't preview podcast grid: \(error)") }
    }
}
