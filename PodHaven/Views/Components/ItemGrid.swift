// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import IdentifiedCollections
import SwiftUI

struct ItemGrid<P: RandomAccessCollection, T: Identifiable, Content: View>: View
where P.Element == T {
  private let items: P
  private let content: (T) -> Content

  init(items: P, @ViewBuilder content: @escaping (T) -> Content) {
    self.items = items
    self.content = content
  }

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
      ForEach(items) { item in
        content(item)
      }
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var isSelecting: Bool = false
  @Previewable @State var isSelected = BindableDictionary<Podcast, Bool>(defaultValue: false)
  @Previewable @State var podcasts: [Podcast] = []
  let gridSize = 12

  VStack {
    Button(isSelecting ? "Stop Selecting" : "Start Selecting") {
      isSelecting.toggle()
    }
    ItemGrid(items: podcasts) { podcast in
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
    } catch { Assert.fatal("Couldn't preview podcast grid: \(error)") }
  }
}
#endif
