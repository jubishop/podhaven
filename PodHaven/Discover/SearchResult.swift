// Copyright Justin Bishop, 2025

import Foundation

struct SearchResult: Sendable, Decodable {
  struct FeedResult: Sendable, Decodable {
    let id: Int
    let url: URL
    let image: URL
    let title: String
    let description: String
    let link: URL
    let lastUpdateTime: Date
    let episodeCount: Int
    let categories: Dictionary<String, String>
  }
  let feeds: [FeedResult]
  let count: Int
}
