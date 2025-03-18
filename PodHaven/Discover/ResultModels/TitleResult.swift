// Copyright Justin Bishop, 2025

import Foundation

struct TitleResult: Decodable, Sendable {
  struct FeedResult: Decodable, Hashable, Identifiable, ResultPodcastConvertible, Sendable {
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
}
