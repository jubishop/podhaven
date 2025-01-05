// Copyright Justin Bishop, 2025 

import Foundation

struct SearchResult: Sendable, Decodable {
  struct FeedResult: Sendable, Decodable {
    let title: String
  }
  let feeds: [FeedResult]
  let count: Int
}
