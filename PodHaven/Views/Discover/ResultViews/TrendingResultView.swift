// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingResultView: View {
  private let currentTokens: [SearchToken]

  init(currentTokens: [SearchToken]) {
    self.currentTokens = currentTokens
  }

  var body: some View {
    Text("Trending")
      .font(.largeTitle)
    List(1...100, id: \.self) { index in
      Text("Entry \(index)")
    }
  }
}

// TODO: Make a preview
