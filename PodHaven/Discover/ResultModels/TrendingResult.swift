// Copyright Justin Bishop, 2025

import Foundation

struct TrendingResult: Decodable, Sendable {
  struct FeedResult: Decodable, Hashable, Identifiable, PodcastConvertible, Sendable {
    let id: Int
    let url: FeedURL
    @OptionalURL var image: URL?
    let title: String
    let description: String
    let trendScore: Int
    let categories: [String: String]
  }
  let feeds: [FeedResult]
  let since: Date
}
