// Copyright Justin Bishop, 2025

import Foundation

struct ItunesLookupResult: Decodable, Sendable {
  struct PodcastInfo: Decodable, Sendable {
    let collectionId: Int
    let collectionName: String
    let feedUrl: String?
    let artworkUrl600: String?
    let collectionViewUrl: String?
    let description: String?
    
    private enum CodingKeys: String, CodingKey {
      case collectionId
      case collectionName
      case feedUrl
      case artworkUrl600
      case collectionViewUrl
      case description
    }
  }
  
  let resultCount: Int
  let results: [PodcastInfo]
  
  var podcastInfo: PodcastInfo? {
    results.first
  }
  
  var feedURL: FeedURL? {
    guard let urlString = podcastInfo?.feedUrl,
          let url = URL(string: urlString) else { return nil }
    return FeedURL(url)
  }
}