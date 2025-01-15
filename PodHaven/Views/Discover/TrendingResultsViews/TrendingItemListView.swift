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

// TODO: Make preview
