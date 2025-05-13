// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchTokenView: View {
  private let token: SearchToken

  init(token: SearchToken) {
    self.token = token
  }

  var body: some View {
    HStack {
      let imageName =
        switch token {
        case .trending:
          "chart.line.uptrend.xyaxis"
        case .allFields:
          "line.3.horizontal.decrease.circle"
        case .titles:
          "text.book.closed"
        case .people:
          "person"
        case .category(_):
          "square.grid.2x2"
        }
      Image(systemName: imageName)
      Text(token.text)
    }
  }
}

#if DEBUG
#Preview {
  VStack(spacing: 32) {
    SearchTokenView(token: .trending)
    SearchTokenView(token: .allFields)
    SearchTokenView(token: .titles)
    SearchTokenView(token: .people)
    SearchTokenView(token: .category("Foo"))
  }
  .preview()
}
#endif
