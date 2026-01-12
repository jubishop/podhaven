// Copyright Justin Bishop, 2025

import SwiftUI

struct ListRowModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .listRowInsets(
        EdgeInsets(
          top: 12,
          leading: 12,
          bottom: 0,
          trailing: 12
        )
      )
      .listRowSeparator(.hidden)
      .dynamicTypeSize(.small ... .xxxLarge)
  }
}

extension View {
  func listRow() -> some View {
    modifier(ListRowModifier())
  }
}
