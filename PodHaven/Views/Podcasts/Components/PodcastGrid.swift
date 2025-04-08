// Copyright Justin Bishop, 2025

import Factory
import GRDB
import IdentifiedCollections
import SwiftUI

struct PodcastGrid<P: RandomAccessCollection, Content: View>: View where P.Element == Podcast {
  private let podcasts: P
  private let content: (Podcast) -> Content

  init(podcasts: P, @ViewBuilder content: @escaping (Podcast) -> Content) {
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
  @Previewable @State var isSelecting: Bool = false
  @Previewable @State var isSelected = BindableDictionary<Podcast, Bool>(defaultValue: false)
  @Previewable @State var podcasts: [Podcast] = []
  let gridSize = 12

  VStack {
    Button(isSelecting ? "Stop Selecting" : "Start Selecting") {
      isSelecting.toggle()
    }
    PodcastGrid(podcasts: podcasts) { podcast in
      SelectablePodcastGridItem(
        viewModel: SelectablePodcastGridItemViewModel(
          isSelected: $isSelected[podcast],
          item: podcast,
          isSelecting: isSelecting
        )
      )
    }
  }
  .preview()
  .task {
    do {
      let repo = Container.shared.repo()
      try await PreviewHelpers.importPodcasts(gridSize)
      var allPodcasts = try await repo.allPodcasts().shuffled()
      allPodcasts[Int.random(in: 0...(gridSize - 1))].image = URL(string: "http://nope.com/0.jpg")!
      podcasts = Array(allPodcasts.prefix(gridSize))
    } catch { fatalError("Couldn't preview podcast grid: \(error)") }
  }
}
