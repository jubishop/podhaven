// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingResultView: View {
  private let category: String
  private let result: TrendingResult?

  init(category: String, result: TrendingResult?) {
    self.category = category
    self.result = result
  }

  var body: some View {
    VStack {
      Text("Trending: \(category)")
        .font(.largeTitle)
      if let result = result {
        List {
          ForEach(result.feeds) { feed in
            Text(feed.title)
          }
        }
      } else {
        Text("Still searching")
        Spacer()
      }
    }
  }
}

// TODO: Make a preview
