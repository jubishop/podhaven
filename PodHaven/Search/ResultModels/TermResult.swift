// Copyright Justin Bishop, 2025

import Foundation

struct TermResult: Decodable, Hashable, PodcastResultConvertible, Sendable {
  struct FeedResult: Decodable, Hashable, Identifiable, FeedResultConvertible, Sendable {
    let id: Int
    let url: FeedURL
    @OptionalURL var image: URL?
    let title: String
    let description: String
    @OptionalURL var link: URL?
    let lastUpdateTime: Date
    let episodeCount: Int
    let categories: [String: String]?
  }
  let feeds: [FeedResult]

  var convertibleFeeds: [any FeedResultConvertible] { feeds }
}
