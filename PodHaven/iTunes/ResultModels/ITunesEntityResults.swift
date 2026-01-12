// Copyright Justin Bishop, 2025

import Foundation
import Tagged

struct ITunesEntityResults: Decodable, Sendable {
  var podcastsWithMetadata: [PodcastWithEpisodeMetadata<UnsavedPodcast>] {
    results.compactMap { try? $0.toPodcastWithEpisodeMetadata() }
  }

  private struct ITunesEntity: Decodable, Sendable {
    static let podcastKind = "podcast"

    private let collectionId: Int?

    private let collectionName: String?
    private let collectionCensoredName: String?

    private let collectionViewUrl: String?
    private let feedUrl: String?

    private let artworkUrl30: String?
    private let artworkUrl60: String?
    private let artworkUrl100: String?
    private let artworkUrl600: String?

    private let collectionDescription: String?
    private let longDescription: String?
    private let description: String?
    private let shortDescription: String?

    private let trackCount: Int?
    private let releaseDate: Date?

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
      guard let feedUrl, let url = URL(string: feedUrl)
      else { return nil }
      return FeedURL(url)
    }

    var link: URL? {
      guard let collectionViewUrl, let url = URL(string: collectionViewUrl)
      else { return nil }
      return url
    }

    var episodeCount: Int { trackCount ?? 0 }
    var mostRecentEpisodeDate: Date? { releaseDate }

    func toPodcastWithEpisodeMetadata() throws -> PodcastWithEpisodeMetadata<UnsavedPodcast>? {
      guard let unsavedPodcast = try toUnsavedPodcast() else { return nil }

      return PodcastWithEpisodeMetadata(
        podcast: unsavedPodcast,
        episodeCount: episodeCount,
        mostRecentEpisodeDate: mostRecentEpisodeDate
      )
    }

    private func toUnsavedPodcast() throws -> UnsavedPodcast? {
      guard isPodcast, let feedURL else { return nil }

      let artworkURLString = artworkUrl600 ?? artworkUrl100 ?? artworkUrl60 ?? artworkUrl30
      guard let imageURLString = artworkURLString, let imageURL = URL(string: imageURLString)
      else { return nil }

      let title = collectionName ?? collectionCensoredName ?? ""
      let description =
        collectionDescription ?? longDescription ?? description ?? shortDescription ?? ""

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
