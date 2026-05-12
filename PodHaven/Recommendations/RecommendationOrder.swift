// Copyright Justin Bishop, 2026

import Foundation

enum RecommendationOrder {
  struct Key: Sendable {
    let score: Float
    let pubDate: Date
    let mediaGUID: MediaGUID
  }

  static func descending(_ lhs: Key, _ rhs: Key) -> Bool {
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    if lhs.pubDate != rhs.pubDate { return lhs.pubDate > rhs.pubDate }
    return lhs.mediaGUID > rhs.mediaGUID
  }
}
