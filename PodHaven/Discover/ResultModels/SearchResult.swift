// Copyright Justin Bishop, 2025

import Foundation

struct SearchResult: Decodable, Sendable {
  struct FeedResult: Decodable, Hashable, Identifiable, PodcastConvertible, Sendable {
    let id: Int
    let url: FeedURL
    @OptionalURL var image: URL?
    let title: String
    let description: String
    let link: URL
    let lastUpdateTime: Date
    let episodeCount: Int
    let categories: [String: String]
  }
  let feeds: [FeedResult]
}
