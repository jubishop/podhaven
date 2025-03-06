// Copyright Justin Bishop, 2025

import Foundation

struct TrendingResult: Sendable, Decodable {
  struct FeedResult: Sendable, Decodable, Identifiable, Hashable {
    let id: Int
    let url: FeedURL
    @OptionalURL var image: URL?
    let title: String
    let description: String
    let trendScore: Int
    let categories: [String: String]

    func toUnsavedPodcast() throws -> UnsavedPodcast {
      guard let image = image
      else { throw Err.msg("No image for \(title)") }

      return try UnsavedPodcast(
        feedURL: url,
        title: title,
        image: image,
        description: description,
        lastUpdate: Date.epoch,
        subscribed: false
      )
    }
  }
  let feeds: [FeedResult]
  let since: Date
}
