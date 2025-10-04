// Copyright Justin Bishop, 2025

import Foundation

struct ITunesEntityResults: Decodable, Sendable {
  var unsavedPodcasts: [UnsavedPodcast] {
    results.compactMap { try? $0.toUnsavedPodcast() }
  }

  func findPodcast(podcastID: ITunesPodcastID) -> ITunesEntity? {
    results.first(where: { $0.isPodcast && $0.podcastID == podcastID })
  }

  struct ITunesEntity: Decodable, Sendable {
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

    var isPodcast: Bool {
      kind == Self.podcastKind
    }

    var podcastID: ITunesPodcastID? {
      guard let collectionId
      else { return nil }
      return ITunesPodcastID(collectionId)
    }

    var feedURL: FeedURL? {
      guard let feedUrlString = feedUrl,
        let url = URL(string: feedUrlString)
      else { return nil }
      return FeedURL(url)
    }

    func toUnsavedPodcast() throws -> UnsavedPodcast? {
      guard isPodcast, let feedURL else { return nil }

      let artworkURLString = artworkUrl600 ?? artworkUrl100 ?? artworkUrl60 ?? artworkUrl30
      guard let imageURLString = artworkURLString, let imageURL = URL(string: imageURLString)
      else { return nil }

      let title =
        collectionName ?? trackName ?? collectionCensoredName ?? trackCensoredName ?? ""
      let description =
        collectionDescription ?? longDescription ?? description ?? shortDescription ?? ""
      let linkString = collectionViewUrl ?? trackViewUrl
      let link = linkString.flatMap(URL.init)

      return try UnsavedPodcast(
        feedURL: feedURL,
        title: title,
        image: imageURL,
        description: description,
        link: link
      )
    }
  }

  private let results: [ITunesEntity]
}
