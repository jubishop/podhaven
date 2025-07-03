// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import IdentifiedCollections

struct EpisodeFeed: Sendable, Equatable {
  let guid: GUID
  let media: MediaURL

  private let rssEpisode: PodcastRSS.Episode

  fileprivate init(rssEpisode: PodcastRSS.Episode) throws {
    self.rssEpisode = rssEpisode
    self.guid = rssEpisode.guid
    self.media = rssEpisode.enclosure.url
  }

  func toUnsavedEpisode(merging episode: Episode? = nil) throws -> UnsavedEpisode {
    Assert.precondition(
      episode == nil || episode?.guid == guid,
      """
      Merging two episodes with different guids?:
        \(String(describing: episode?.guid)), \(guid)
      """
    )

    return try UnsavedEpisode(
      podcastId: episode?.podcastId,
      guid: guid,
      media: media,
      title: rssEpisode.title,
      pubDate: rssEpisode.pubDate ?? episode?.pubDate,
      duration: duration ?? episode?.duration,
      description: rssEpisode.description ?? episode?.description,
      link: rssEpisode.link ?? episode?.link,
      image: rssEpisode.iTunes.image?.href ?? episode?.image,
      completionDate: episode?.completionDate,
      currentTime: episode?.currentTime,
      queueOrder: episode?.queueOrder
    )
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
    return CMTime.inSeconds(Double(seconds))
  }

  // MARK: - Equatable

  static func == (lhs: EpisodeFeed, rhs: EpisodeFeed) -> Bool {
    lhs.guid == rhs.guid
  }
}

struct PodcastFeed: Sendable, Stringable {
  // MARK: - Static Parsing Methods

  static func parse(_ url: FeedURL) async throws(FeedError) -> PodcastFeed {
    try await FeedError.catch {
      let data = try await URLSession.shared.validatedData(from: url.rawValue)
      return try await parse(data, from: url)
    }
  }

  static func parse(_ data: Data, from: FeedURL) async throws(FeedError) -> PodcastFeed {
    do {
      let rssPodcast = try await PodcastRSS.parse(data)
      return PodcastFeed(rssPodcast: rssPodcast, from: from)
    } catch {
      throw FeedError.parseFailure(url: from, caught: error)
    }
  }

  // MARK: - Instance Definition

  let episodes: [EpisodeFeed]

  let feedURL: FeedURL
  private let rssPodcast: PodcastRSS.Podcast
  private let link: URL?
  private let image: URL

  private init(rssPodcast: PodcastRSS.Podcast, from: FeedURL) {
    self.rssPodcast = rssPodcast
    self.feedURL = rssPodcast.feedURL ?? from
    self.link = rssPodcast.link
    self.image = rssPodcast.iTunes.image.href
    self.episodes = rssPodcast.episodes.compactMap { rssEpisode in
      try? EpisodeFeed(rssEpisode: rssEpisode)
    }
  }

  func toUnsavedPodcast(subscribed: Bool? = nil, lastUpdate: Date? = nil) throws(FeedError)
    -> UnsavedPodcast
  {
    try FeedError.catch {
      try UnsavedPodcast(
        feedURL: rssPodcast.iTunes.newFeedURL ?? feedURL,
        title: rssPodcast.title,
        image: image,
        description: rssPodcast.description,
        link: link,
        lastUpdate: lastUpdate,
        subscribed: subscribed
      )
    }
  }

  func toUnsavedPodcast(merging unsavedPodcast: UnsavedPodcast) throws(FeedError) -> UnsavedPodcast
  {
    Assert.precondition(
      unsavedPodcast.feedURL == feedURL,
      """
      Merging two podcasts with different feedURLs?:
        \(feedURL) != \(unsavedPodcast.feedURL)
      """
    )

    return try toUnsavedPodcast(
      subscribed: unsavedPodcast.subscribed,
      lastUpdate: unsavedPodcast.lastUpdate
    )
  }

  func toEpisodeArray(merging podcastSeries: PodcastSeries? = nil)
    -> IdentifiedArray<GUID, UnsavedEpisode>
  {
    // Two UnsavedEpisodes may have the same GUID
    IdentifiedArray(
      episodes.compactMap { episodeFeed in
        try? episodeFeed.toUnsavedEpisode(
          merging: podcastSeries?.episodes[id: episodeFeed.guid]
        )
      },
      id: \.guid,
      uniquingIDsWith: { a, b in
        // Keep whichever is the newest
        a.pubDate >= b.pubDate ? a : b
      }
    )
  }

  // MARK: - Stringable

  var toString: String { "(\(feedURL.toString)) - \(rssPodcast.title)" }

  // MARK: - Hashable

  func hash(into hasher: inout Hasher) {
    hasher.combine(feedURL)
  }

  // MARK: - Equatable

  static func == (lhs: PodcastFeed, rhs: PodcastFeed) -> Bool {
    lhs.feedURL == rhs.feedURL
  }
}
