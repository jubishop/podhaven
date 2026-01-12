// Copyright Justin Bishop, 2026

import SwiftUI

struct ListRowSeparatorModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.bottom, 12)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(Color(uiColor: .separator))
          .frame(height: 0.5)
      }
  }
}

extension View {
  func listRowSeparator() -> some View {
    modifier(ListRowSeparatorModifier())
  }
}
