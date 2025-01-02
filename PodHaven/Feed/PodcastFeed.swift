// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation

struct EpisodeFeed: Sendable {
  let guid: String
  let media: URL

  private let rssEpisode: PodcastRSS.Episode

  fileprivate init(rssEpisode: PodcastRSS.Episode) throws {
    guard let media = try? URL(string: rssEpisode.enclosure.url)?.convertToValidURL()
    else { throw FeedError.failedConversion("EpisodeFeed requires media URL") }
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
    guard let urlString = rssEpisode.link, let url = URL(string: urlString)
    else { return nil }

    return url
  }

  private var image: URL? {
    guard let urlString = rssEpisode.iTunes.image?.href, let url = URL(string: urlString)
    else { return nil }

    return url
  }

  private var duration: CMTime? {
    guard let timeComponents = rssEpisode.iTunes.duration?.split(separator: ":"),
      timeComponents.count <= 3
    else { return CMTime.zero }

    var seconds = 0
    var multiplier = 1
    for value in timeComponents.reversed() {
      guard let value = Int(value) else { return CMTime.zero }
      seconds += multiplier * value
      multiplier *= 60
    }
    return CMTime.inSeconds(Double(seconds))
  }
}

struct PodcastFeed: Sendable, Equatable {
  // MARK: - Static Parsing Methods

  static func parse(_ url: URL) async throws -> PodcastFeed {
    guard let data = try? Data(contentsOf: url) else { throw FeedError.failedLoad(url) }
    return try await parse(data)
  }

  static func parse(_ data: Data) async throws -> PodcastFeed {
    let rssPodcast = try await PodcastRSS.parse(data)
    return PodcastFeed(rssPodcast: rssPodcast)
  }

  // MARK: - Instance Definition

  let episodes: [EpisodeFeed]

  private let rssPodcast: PodcastRSS.Podcast

  private init(rssPodcast: PodcastRSS.Podcast) {
    self.rssPodcast = rssPodcast
    self.episodes = rssPodcast.episodes.compactMap { rssEpisode in
      try? EpisodeFeed(rssEpisode: rssEpisode)
    }
  }

  func toPodcast(mergingExisting existingPodcast: Podcast) -> Podcast? {
    guard
      let unsavedPodcast = toUnsavedPodcast(
        feedURL: existingPodcast.feedURL,
        mergingExisting: existingPodcast
      )
    else { return nil }

    return Podcast(id: existingPodcast.id, from: unsavedPodcast)
  }

  // TODO: Remove need for feedURL here
  func toUnsavedPodcast(feedURL: URL, mergingExisting existingPodcast: Podcast? = nil)
    -> UnsavedPodcast?
  {
    try? UnsavedPodcast(
      feedURL: self.newFeedURL ?? feedURL,
      title: rssPodcast.title,
      link: link ?? existingPodcast?.link,
      image: image ?? existingPodcast?.image,
      description: rssPodcast.description,
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

  private var link: URL? {
    guard let url = URL(string: rssPodcast.link)
    else { return nil }

    return url
  }

  private var image: URL? {
    guard let url = URL(string: rssPodcast.iTunes.image.href)
    else { return nil }

    return url
  }

  // MARK: - Equatable

  static func == (lhs: PodcastFeed, rhs: PodcastFeed) -> Bool {
    lhs.rssPodcast == rhs.rssPodcast
  }
}
