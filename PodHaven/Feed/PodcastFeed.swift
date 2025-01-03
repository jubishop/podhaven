// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct EpisodeFeed: Sendable, Equatable {
  let guid: String
  let media: URL

  private let rssEpisode: PodcastRSS.Episode

  fileprivate init(rssEpisode: PodcastRSS.Episode) throws {
    guard let media = URL(string: rssEpisode.enclosure.url)
    else { throw FeedError.failedConversion("EpisodeFeed invalid media URL") }

    self.rssEpisode = rssEpisode
    self.guid = rssEpisode.guid
    self.media = media
  }

  func toUnsavedEpisode(mergingExisting existingEpisode: Episode? = nil) throws -> UnsavedEpisode {
    precondition(
      existingEpisode == nil || existingEpisode?.guid == guid,
      "Merging two episodes with different guids?"
    )

    return try UnsavedEpisode(
      guid: guid,
      podcastId: existingEpisode?.podcastId,
      title: rssEpisode.title,
      media: media,
      currentTime: existingEpisode?.currentTime,
      completed: existingEpisode?.completed,
      duration: duration ?? existingEpisode?.duration,
      pubDate: rssEpisode.pubDate ?? existingEpisode?.pubDate,
      description: rssEpisode.description ?? existingEpisode?.description,
      link: link ?? existingEpisode?.link,
      image: image ?? existingEpisode?.image,
      queueOrder: existingEpisode?.queueOrder
    )
  }

  func toEpisode(mergingExisting existingEpisode: Episode) throws -> Episode {
    Episode(
      id: existingEpisode.id,
      from: try toUnsavedEpisode(mergingExisting: existingEpisode)
    )
  }

  // MARK: - Private Helpers

  private var link: URL? {
    guard let urlString = rssEpisode.link
    else { return nil }

    return URL(string: urlString)
  }

  private var image: URL? {
    guard let urlString = rssEpisode.iTunes.image?.href
    else { return nil }

    return URL(string: urlString)
  }

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

struct PodcastFeed: Sendable, Equatable {
  // MARK: - Static Parsing Methods

  static func parse(_ url: URL) async throws -> PodcastFeed {
    guard let data = try? Data(contentsOf: url) else { throw FeedError.failedLoad(url) }
    return try await parse(data, from: url)
  }

  static func parse(_ data: Data, from: URL) async throws -> PodcastFeed {
    let rssPodcast = try await PodcastRSS.parse(data)
    return try PodcastFeed(rssPodcast: rssPodcast, from: from)
  }

  // MARK: - Instance Definition

  let episodes: [EpisodeFeed]

  private let rssPodcast: PodcastRSS.Podcast
  private let feedURL: URL
  private let link: URL?
  private let image: URL

  private init(rssPodcast: PodcastRSS.Podcast, from: URL) throws {
    guard let image = URL(string: rssPodcast.iTunes.image.href)
    else { throw FeedError.failedConversion("PodcastFeed invalid media URL") }

    self.rssPodcast = rssPodcast
    self.feedURL = rssPodcast.feedURL ?? from
    self.link = URL(string: rssPodcast.link ?? "")
    self.image = image
    self.episodes = rssPodcast.episodes.compactMap { rssEpisode in
      try? EpisodeFeed(rssEpisode: rssEpisode)
    }
  }

  func toPodcast(mergingExisting existingPodcast: Podcast) throws -> Podcast {
    let unsavedPodcast = try toUnsavedPodcast(mergingExisting: existingPodcast)
    return Podcast(id: existingPodcast.id, from: unsavedPodcast)
  }

  func toUnsavedPodcast(mergingExisting existingPodcast: Podcast? = nil) throws -> UnsavedPodcast {
    precondition(
      existingPodcast == nil || existingPodcast?.feedURL == feedURL,
      "Merging two podcasts with different feedURLs?"
    )

    return try UnsavedPodcast(
      feedURL: newFeedURL ?? feedURL,
      title: rssPodcast.title,
      image: image,
      description: rssPodcast.description,
      link: link,
      lastUpdate: existingPodcast?.lastUpdate
    )
  }

  // MARK: - Private Helpers

  private var newFeedURL: URL? {
    guard let newFeedURLString = rssPodcast.iTunes.newFeedURL,
      let newFeedURL = URL(string: newFeedURLString)
    else { return nil }

    return newFeedURL
  }

  // MARK: - Equatable

  static func == (lhs: PodcastFeed, rhs: PodcastFeed) -> Bool {
    lhs.feedURL == rhs.feedURL
  }
}
