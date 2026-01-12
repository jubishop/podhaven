// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import Tagged

extension Container {
  var podcastFeedSession: Factory<any DataFetchable> {
    Factory(self) {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.allowsCellularAccess = true
      configuration.waitsForConnectivity = true
      configuration.timeoutIntervalForRequest = Double(10)
      configuration.timeoutIntervalForResource = Double(30)
      return URLSession(configuration: configuration)
    }
    .scope(.cached)
  }
}

// MARK: - EpisodeFeed

struct EpisodeFeed: Sendable, Equatable {
  let guid: GUID
  let mediaURL: MediaURL

  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }

  private let rssEpisode: PodcastRSS.Episode

  fileprivate init(rssEpisode: PodcastRSS.Episode) throws(ParseError) {
    guard let mediaURL = rssEpisode.enclosure?.url
    else { throw ParseError.missingMediaURL(rssEpisode.title) }

    let validatedMediaURL: MediaURL
    do {
      validatedMediaURL = try mediaURL.convertToHTTPSURL()
    } catch {
      throw ParseError.invalidMediaURL(mediaURL)
    }

    self.rssEpisode = rssEpisode
    self.guid = rssEpisode.guid ?? GUID(validatedMediaURL.absoluteString)
    self.mediaURL = validatedMediaURL
  }

  func toUnsavedEpisode(merging episode: Episode? = nil) throws(FeedError) -> UnsavedEpisode {
    // We intentionally dont merge other fields from Episode because we will have potentially stale
    // data compared to the database.  We should only use rssColumnAssignments() for updating.
    try FeedError.catch {
      try UnsavedEpisode(
        podcastId: episode?.podcastId,
        guid: guid,
        mediaURL: mediaURL,
        title: rssEpisode.title,
        pubDate: rssEpisode.pubDate ?? episode?.pubDate,
        duration: duration ?? episode?.duration,
        description: rssEpisode.description ?? episode?.description,
        link: rssEpisode.link ?? episode?.link,
        image: rssEpisode.iTunes.image?.href ?? episode?.image
      )
    }
  }

  // MARK: - Private Helpers

  private var duration: CMTime? {
    guard let timeComponents = rssEpisode.iTunes.duration?.split(separator: ":"),
      timeComponents.count <= 3
    else { return nil }

    var seconds = 0
    var multiplier = 1
    for value in timeComponents.reversed() {
      guard let value = Int(value) else { return nil }
      seconds += multiplier * value
      multiplier *= 60
    }
    return CMTime.seconds(Double(seconds))
  }

  // MARK: - Equatable

  static func == (lhs: EpisodeFeed, rhs: EpisodeFeed) -> Bool {
    lhs.guid == rhs.guid
  }
}

// MARK: - PodcastFeed

struct PodcastFeed: Sendable, Stringable {
  private static let log = Log.as(LogSubsystem.Feed.podcast)

  // MARK: - Static Parsing Methods

  static func parse(_ url: FeedURL) async throws(FeedError) -> PodcastFeed {
    try await FeedError.catch {
      let data = try await Container.shared.podcastFeedSession().validatedData(from: url.rawValue)
      return try await parse(data, from: url)
    }
  }

  static func parse(_ downloadData: DownloadData) async throws(FeedError) -> PodcastFeed {
    try await FeedError.catch {
      try await parse(downloadData.data, from: FeedURL(downloadData.url))
    }
  }

  static func parse(_ data: Data, from: FeedURL) async throws(FeedError) -> PodcastFeed {
    do {
      log.trace("Parsing data of size \(data.count) from \(from)")

      let rssPodcast = try await PodcastRSS.parse(data)
      return try PodcastFeed(rssPodcast: rssPodcast, from: from)
    } catch {
      throw FeedError.parseFailure(url: from, caught: error)
    }
  }

  // MARK: - Instance Definition

  let feedURL: FeedURL

  private let rssPodcast: PodcastRSS.Podcast
  private let link: URL?
  private let image: URL
  private let episodeFeeds: [EpisodeFeed]

  private init(rssPodcast: PodcastRSS.Podcast, from: FeedURL) throws {
    self.rssPodcast = rssPodcast
    self.feedURL = try (rssPodcast.feedURL ?? from).convertToHTTPSURL()
    self.link = rssPodcast.link
    self.image = rssPodcast.iTunes.image.href
    self.episodeFeeds = rssPodcast.episodes.compactMap { rssEpisode in
      do {
        return try EpisodeFeed(rssEpisode: rssEpisode)
      } catch {
        Self.log.error(error)
        return nil
      }
    }
  }

  var updatedFeedURL: FeedURL {
    rssPodcast.iTunes.newFeedURL ?? feedURL
  }

  func toUnsavedSeries(merging podcastSeries: PodcastSeries? = nil)
    throws(FeedError) -> UnsavedPodcastSeries
  {
    UnsavedPodcastSeries(
      unsavedPodcast: try toUnsavedPodcast(merging: podcastSeries?.podcast),
      unsavedEpisodes: toUnsavedEpisodes(merging: podcastSeries?.episodes)
    )
  }

  func toUnsavedPodcast(merging podcast: Podcast? = nil) throws(FeedError) -> UnsavedPodcast {
    try FeedError.catch {
      try UnsavedPodcast(
        feedURL: updatedFeedURL,
        title: rssPodcast.title,
        image: image,
        description: rssPodcast.description,
        link: link ?? podcast?.link
      )
    }
  }

  func toUnsavedEpisodes(merging episodes: IdentifiedArrayOf<Episode>? = nil)
    -> IdentifiedArrayOf<UnsavedEpisode>
  {
    let existingEpisodesByMediaURL: [MediaURL: Episode]
    let existingEpisodesByGUID: [GUID: Episode]
    if let episodes {
      existingEpisodesByMediaURL = Dictionary(
        uniqueKeysWithValues: episodes.map { ($0.mediaGUID.mediaURL, $0) }
      )
      existingEpisodesByGUID = Dictionary(
        uniqueKeysWithValues: episodes.map { ($0.mediaGUID.guid, $0) }
      )
    } else {
      existingEpisodesByMediaURL = [:]
      existingEpisodesByGUID = [:]
    }

    let allEpisodes =
      episodeFeeds.compactMap { episodeFeed -> UnsavedEpisode? in
        do {
          return try episodeFeed.toUnsavedEpisode(
            merging: existingEpisodesByMediaURL[episodeFeed.mediaURL]
              ?? existingEpisodesByGUID[episodeFeed.guid]
          )
        } catch {
          Self.log.error(error)
          return nil
        }
      }
      .sorted { $0.pubDate > $1.pubDate }

    var seenGUIDs = Set<GUID>(capacity: allEpisodes.count)
    var seenMediaURLs = Set<MediaURL>(capacity: allEpisodes.count)
    return IdentifiedArrayOf<UnsavedEpisode>(
      uniqueElements: allEpisodes.compactMap { episode in
        if seenGUIDs.contains(episode.guid) || seenMediaURLs.contains(episode.mediaURL) {
          return nil
        }

        seenGUIDs.insert(episode.guid)
        seenMediaURLs.insert(episode.mediaURL)
        return episode
      }
    )
  }

  // MARK: - Stringable

  var toString: String { "(\(updatedFeedURL.toString)) - \(rssPodcast.title)" }

  // MARK: - Hashable

  func hash(into hasher: inout Hasher) {
    hasher.combine(updatedFeedURL)
  }

  // MARK: - Equatable

  static func == (lhs: PodcastFeed, rhs: PodcastFeed) -> Bool {
    lhs.updatedFeedURL == rhs.updatedFeedURL
  }
}
