// Copyright Justin Bishop, 2025

import Foundation

struct ITunesLookupResult: Decodable, Sendable {
  func findEpisode(episodeID: ITunesEpisodeID) -> ITunesTrackInfo? {
    results.first(where: { $0.episodeID == episodeID })
  }

  var feedURL: FeedURL? {
    results.compactMap(\.feedURL).first
  }

  struct ITunesTrackInfo: Decodable, Sendable {
    static let episodeKind = "podcast-episode"
    static let podcastKind = "podcast"

    private let collectionId: Int?
    private let trackId: Int?
    private let episodeGuid: String?

    private let collectionName: String?
    private let trackName: String?
    private let collectionCensoredName: String?
    private let trackCensoredName: String?

    private let collectionViewUrl: String?
    private let trackViewUrl: String?
    private let feedUrl: String?
    private let episodeUrl: String?

    private let artworkUrl30: String?
    private let artworkUrl60: String?
    private let artworkUrl100: String?
    private let artworkUrl600: String?

    private let shortDescription: String?
    private let longDescription: String?
    private let collectionDescription: String?
    private let description: String?

    private let kind: String?
    private let wrapperType: String?

    var episodeID: ITunesEpisodeID? {
      guard kind == Self.episodeKind,
        let trackId
      else { return nil }
      return ITunesEpisodeID(trackId)
    }

    var podcastID: ITunesPodcastID? {
      guard kind == Self.podcastKind,
        let collectionId
      else { return nil }
      return ITunesEpisodeID(collectionId)
    }

    var feedURL: FeedURL? {
      guard kind == Self.podcastKind,
        let feedUrlString = feedUrl,
        let url = URL(string: feedUrlString)
      else { return nil }
      return FeedURL(url)
    }

    var mediaURL: MediaURL? {
      guard let urlString = episodeUrl,
        let url = URL(string: urlString)
      else { return nil }
      return MediaURL(url)
    }

    var guid: GUID? {
      guard let guidString = episodeGuid
      else { return nil }
      return GUID(guidString)
    }
  }

  private let results: [ITunesTrackInfo]
}
