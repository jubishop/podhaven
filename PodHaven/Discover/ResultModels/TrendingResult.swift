// Copyright Justin Bishop, 2025

import Foundation

struct TrendingResult: Decodable, Sendable {
  struct FeedResult: Decodable, Hashable, Identifiable, ResultPodcastConvertible, Sendable {
    let id: Int
    let url: FeedURL
    @OptionalURL var image: URL?
    let title: String
    let description: String
    let trendScore: Int
    let categories: [String: String]

    // MARK: - ResultPodcastConvertible

    var link: URL? { nil }
  }
  let feeds: [FeedResult]
  let since: Date
}
