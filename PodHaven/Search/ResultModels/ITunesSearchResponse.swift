// Copyright Justin Bishop, 2025

import Foundation

struct ITunesSearchResponse: Decodable, Sendable {
  let resultCount: Int
  let results: [Podcast]

  var podcasts: [Podcast] {
    results.filter {
      $0.kind == "podcast" || $0.wrapperType == "track" || $0.wrapperType == "collection"
    }
  }

  struct Podcast: Decodable, Sendable {
    let collectionId: Int?
    let trackId: Int?
    let artistName: String?
    let collectionName: String?
    let trackName: String?
    let collectionCensoredName: String?
    let trackCensoredName: String?
    let collectionViewUrl: String?
    let trackViewUrl: String?
    let feedUrl: String?
    let artworkUrl30: String?
    let artworkUrl60: String?
    let artworkUrl100: String?
    let artworkUrl600: String?
    let shortDescription: String?
    let longDescription: String?
    let collectionDescription: String?
    let description: String?
    let primaryGenreName: String?
    let country: String?
    let currency: String?
    let contentAdvisoryRating: String?
    let kind: String?
    let wrapperType: String?
    let genreIds: [String]?
    let genres: [String]?
  }
}
