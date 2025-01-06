// Copyright Justin Bishop, 2025

import Foundation

struct TrendingResult: Sendable, Decodable {
  struct FeedResult: Sendable, Decodable {
    let id: Int
    let url: URL
    let image: URL
    let title: String
    let description: String
    let trendScore: Int
    let categories: Dictionary<String, String>
  }
  let feeds: [FeedResult]
  let since: Date
}

