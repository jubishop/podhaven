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

    private let kind: String?
    private let collectionId: Int?
    private let trackId: Int?
    private let episodeUrl: String?
    private let episodeGuid: String?
    private let feedUrl: String?

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
