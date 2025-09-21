// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import IdentifiedCollections
import SwiftUI

struct ItemGrid<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
  private let items: Data
  private let idKeyPath: KeyPath<Data.Element, ID>
  private let minimumGridSize: CGFloat
  private let content: (Data.Element) -> Content

  init(
    items: Data,
    id: KeyPath<Data.Element, ID>,
    minimumGridSize: CGFloat? = nil,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.items = items
    idKeyPath = id
    self.minimumGridSize = minimumGridSize ?? CGFloat(100)
    self.content = content
  }

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumGridSize))]) {
      ForEach(items, id: idKeyPath) { item in
        content(item)
      }
    }
  }
}

extension ItemGrid where Data.Element: Identifiable, ID == Data.Element.ID {
  init(
    items: Data,
    minimumGridSize: CGFloat? = nil,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.init(items: items, id: \.id, minimumGridSize: minimumGridSize, content: content)
  }
}
