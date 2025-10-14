// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import IdentifiedCollections
import SwiftUI

struct ItemGrid<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Identifiable {
  private let items: Data
  private let minimumGridSize: CGFloat
  private let content: (Data.Element) -> Content

  init(
    items: Data,
    minimumGridSize: CGFloat? = nil,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.items = items
    self.minimumGridSize = minimumGridSize ?? CGFloat(100)
    self.content = content
  }

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumGridSize))]) {
      ForEach(items) { item in
        content(item)
      }
    }
  }
}
