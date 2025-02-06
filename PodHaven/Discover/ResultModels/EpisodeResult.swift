// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct EpisodeResult: Sendable, Decodable {
  struct ItemResult: Sendable, Decodable {
    let id: Int
    let guid: GUID
    let title: String
    @OptionalURL var link: URL?
    let description: String
    let datePublished: Date
    let enclosureUrl: MediaURL
    let duration: CMTime
    @OptionalURL var image: URL?
    let feedUrl: FeedURL
    let feedImage: URL
    let feedTitle: String
  }
  let items: [ItemResult]
}
