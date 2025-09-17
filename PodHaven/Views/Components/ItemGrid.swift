// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import IdentifiedCollections
import SwiftUI

struct ItemGrid<P: RandomAccessCollection, T: Identifiable, Content: View>: View
where P.Element == T {
  let minimumGridSize = CGFloat(100)

  private let items: P
  private let content: (T) -> Content

  init(items: P, @ViewBuilder content: @escaping (T) -> Content) {
    self.items = items
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
