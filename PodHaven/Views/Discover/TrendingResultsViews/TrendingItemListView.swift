// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemListView: View {
  private let feedResult: TrendingResult.FeedResult

  init(feedResult: TrendingResult.FeedResult) {
    self.feedResult = feedResult
  }

  var body: some View {
    NavigationLink(
      value: feedResult,
      label: { Text(feedResult.title) }
    )
  }
}

#Preview {
  @Previewable @State var feedResult: TrendingResult.FeedResult?

  NavigationStack {
    List {
      if let feedResult = feedResult {
        TrendingItemListView(feedResult: feedResult)
      } else {
        Text("No trending result found")
      }
    }
  }
  .preview()
  .task {
    feedResult = try! await PreviewHelpers.loadFeedResult()
  }
}
