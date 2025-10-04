// Copyright Justin Bishop, 2025

import Foundation

struct ITunesEntityResults: Decodable, Sendable {
  var unsavedPodcasts: [ITunesPodcastID: UnsavedPodcast] {
    Dictionary(
      uniqueKeysWithValues: podcasts.compactMap { result -> (ITunesPodcastID, UnsavedPodcast)? in
        guard let id = result.podcastID,
          let podcast = try? result.toUnsavedPodcast()
        else { return nil }
        return (id, podcast)
      }
    )
  }

  var podcasts: [ITunesEntity] {
    results.filter(\.isPodcast)
  }

  var episodes: [ITunesEntity] {
    results.filter(\.isEpisode)
  }

  func findPodcast(podcastID: ITunesPodcastID) -> ITunesEntity? {
    results.first(where: { $0.isPodcast && $0.podcastID == podcastID })
  }

  func findEpisode(episodeID: ITunesEpisodeID) -> ITunesEntity? {
    results.first(where: { $0.isEpisode && $0.episodeID == episodeID })
  }

  struct ITunesEntity: Decodable, Sendable {
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

    var isPodcast: Bool {
      kind == Self.podcastKind
    }

    var isEpisode: Bool {
      kind == Self.episodeKind
    }

    var episodeID: ITunesEpisodeID? {
      guard let trackId
      else { return nil }
      return ITunesEpisodeID(trackId)
    }

    var podcastID: ITunesPodcastID? {
      guard let collectionId
      else { return nil }
      return ITunesEpisodeID(collectionId)
    }

    var feedURL: FeedURL? {
      guard let feedUrlString = feedUrl,
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
