// Copyright Justin Bishop, 2025

import Foundation

struct SearchResult: Sendable, Decodable {
  struct FeedResult: Sendable, Decodable, Identifiable, Hashable {
    let id: Int
    let url: FeedURL
    let image: URL
    let title: String
    let description: String
    let link: URL
    let lastUpdateTime: Date
    let episodeCount: Int
    let categories: [String: String]
  }
  let feeds: [FeedResult]
}
