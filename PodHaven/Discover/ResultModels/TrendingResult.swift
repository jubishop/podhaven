// Copyright Justin Bishop, 2025

import Foundation

struct TrendingResult: Sendable, Decodable {
  struct FeedResult: Sendable, Decodable, Identifiable, Hashable {
    let id: Int
    let url: URL
    let image: URL
    let title: String
    let description: String
    let trendScore: Int
    let categories: [String: String]

    func toUnsavedPodcast() throws -> UnsavedPodcast {
      try UnsavedPodcast(
        feedURL: url,
        title: title,
        image: image,
        description: description,
        lastUpdate: Date(timeIntervalSince1970: 0),
        subscribed: false
      )
    }
  }
  let feeds: [FeedResult]
  let since: Date
}

