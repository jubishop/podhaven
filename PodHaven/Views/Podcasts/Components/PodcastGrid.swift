// Copyright Justin Bishop, 2025

import Factory
import GRDB
import IdentifiedCollections
import SwiftUI

struct PodcastGrid<Content: View>: View {
  private let podcasts: PodcastArray
  private let content: (Podcast) -> Content

  init(podcasts: PodcastArray, @ViewBuilder content: @escaping (Podcast) -> Content) {
    self.podcasts = podcasts
    self.content = content
  }

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
      ForEach(podcasts) { podcast in
        content(podcast)
      }
    }
  }
}

#Preview {
  @Previewable @State var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)
  let gridSize = 12

  PodcastGrid(podcasts: podcasts) { podcast in
    SelectablePodcastGridItem(viewModel: SelectablePodcastGridItemViewModel(
      isSelected: .constant(false),
      item: podcast,
      isSelecting: false
    ))
  }
  .preview()
  .task {
    do {

      let repo = Container.shared.repo()
      try await PreviewHelpers.importPodcasts(gridSize)
      var allPodcasts = try await repo.allPodcasts().shuffled()
      allPodcasts[Int.random(in: 0...(gridSize - 1))].image = URL(string: "http://nope.com/0.jpg")!
      podcasts = IdentifiedArray(uniqueElements: allPodcasts.prefix(gridSize), id: \Podcast.feedURL)
    } catch { fatalError("Couldn't preview podcast grid: \(error)") }
  }
}
