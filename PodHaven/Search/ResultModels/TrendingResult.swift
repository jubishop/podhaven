// Copyright Justin Bishop, 2025

import Foundation

struct TrendingResult: Decodable, Hashable, PodcastResultConvertible, Sendable {
  struct FeedResult: Decodable, Hashable, Identifiable, FeedResultConvertible, Sendable {
    let id: Int
    let url: FeedURL
    @OptionalURL var image: URL?
    let title: String
    let description: String
    let trendScore: Int
    let categories: [String: String]

    // MARK: - FeedResultConvertible

    var link: URL? { nil }
  }
  let feeds: [FeedResult]
  let since: Date

  var convertibleFeeds: [any FeedResultConvertible] { feeds }
}
