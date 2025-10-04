// Copyright Justin Bishop, 2025

import Foundation

struct ITunesSearchResponse: Decodable, Sendable {
  var unsavedPodcasts: [ITunesPodcastID: UnsavedPodcast] {
    Dictionary(
      uniqueKeysWithValues: podcasts.compactMap { result -> (ITunesPodcastID, UnsavedPodcast)? in
        guard let id = result.itunesID,
          let podcast = try? result.toUnsavedPodcast()
        else { return nil }
        return (id, podcast)
      }
    )
  }

  private var podcasts: [PodcastResult] {
    results.filter(\.isPodcast)
  }

  private struct PodcastResult: Decodable, Sendable {
    private let collectionId: Int?
    private let trackId: Int?
    private let collectionName: String?
    private let trackName: String?
    private let collectionCensoredName: String?
    private let trackCensoredName: String?
    private let collectionViewUrl: String?
    private let trackViewUrl: String?
    private let feedUrl: String?
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
      kind == "podcast" || wrapperType == "track" || wrapperType == "collection"
    }

    var itunesID: ITunesPodcastID? {
      if let collectionId { return ITunesPodcastID(rawValue: collectionId) }
      if let trackId { return ITunesPodcastID(rawValue: trackId) }
      return nil
    }

    func toUnsavedPodcast() throws -> UnsavedPodcast? {
      guard let feedUrl, let feedURL = URL(string: feedUrl)
      else { return nil }

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
        feedURL: FeedURL(feedURL),
        title: title,
        image: imageURL,
        description: description,
        link: link
      )
    }
  }

  private let results: [PodcastResult]
}
