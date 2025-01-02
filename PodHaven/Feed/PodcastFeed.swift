// Copyright Justin Bishop, 2024

import AVFoundation
@preconcurrency import FeedKit
import Foundation

typealias ParseResult = Result<PodcastFeed, FeedError>

struct EpisodeFeed: Sendable {
  let guid: String
  let media: URL

  private let rssFeedItem: RSSFeedItem

  fileprivate init(rssFeedItem: RSSFeedItem) throws {
    guard let feedItemGUID = rssFeedItem.guid, let guid = feedItemGUID.value
    else { throw FeedError.failedParse("EpisodeFeed requires a GUID") }
    guard let urlString = rssFeedItem.enclosure?.attributes?.url,
      let media = try? URL(string: urlString)?.convertToValidURL()
    else { throw FeedError.failedParse("EpisodeFeed requires media URL") }
    self.rssFeedItem = rssFeedItem
    self.guid = guid
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
      media: media,
      currentTime: existingEpisode?.currentTime,
      completed: existingEpisode?.completed,
      duration: duration ?? existingEpisode?.duration,
      pubDate: pubDate ?? existingEpisode?.pubDate,
      title: title ?? existingEpisode?.title,
      description: description ?? existingEpisode?.description,
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

  private var pubDate: Date? {
    rssFeedItem.pubDate
  }

  private var title: String? {
    rssFeedItem.title ?? rssFeedItem.iTunes?.iTunesTitle
  }

  private var description: String? {
    rssFeedItem.description ?? rssFeedItem.iTunes?.iTunesSummary
  }

  private var link: URL? {
    guard let urlString = rssFeedItem.link, let url = URL(string: urlString)
    else { return nil }
    return url
  }

  private var image: URL? {
    guard let urlString = rssFeedItem.iTunes?.iTunesImage?.attributes?.href,
      let url = URL(string: urlString)
    else { return nil }
    return url
  }

  private var duration: CMTime? {
    guard let timeInterval = rssFeedItem.iTunes?.iTunesDuration
    else { return nil }
    return CMTime.inSeconds(timeInterval)
  }
}

struct PodcastFeed: Sendable, Equatable {
  // MARK: - Static Parsing Methods

  static func parse(_ url: URL) async -> ParseResult {
    guard let data = try? Data(contentsOf: url)
    else { return .failure(.failedLoad(url)) }
    return await parse(data)
  }

  static func parse(_ data: Data) async -> ParseResult {
    let parser = FeedParser(data: data)
    return await withCheckedContinuation { continuation in
      switch parser.parse() {
      case .success(let feed):
        guard let rssFeed = feed.rssFeed
        else { return continuation.resume(returning: .failure(.noRSS)) }
        continuation.resume(returning: .success(PodcastFeed(rssFeed: rssFeed)))
      case .failure(let error):
        continuation.resume(returning: .failure(.failedParse(String(describing: error))))
      }
    }
  }

  // MARK: - Instance Definition

  let items: [EpisodeFeed]

  private let rssFeed: RSSFeed

  private init(rssFeed: RSSFeed) {
    self.rssFeed = rssFeed
    self.items = (rssFeed.items ?? [])
      .compactMap { rssFeedItem in
        try? EpisodeFeed(rssFeedItem: rssFeedItem)
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

  func toUnsavedPodcast(feedURL: URL, mergingExisting existingPodcast: Podcast? = nil)
    -> UnsavedPodcast?
  {
    try? UnsavedPodcast(
      feedURL: self.feedURL ?? feedURL,
      // TODO: Title will become non-optional
      title: title ?? existingPodcast?.title ?? "Remove me",
      link: link ?? existingPodcast?.link,
      image: image ?? existingPodcast?.image,
      description: description ?? existingPodcast?.description,
      lastUpdate: existingPodcast?.lastUpdate
    )
  }

  // MARK: - Private Helpers

  private var feedURL: URL? {
    guard let newFeedURLString = rssFeed.iTunes?.iTunesNewFeedURL,
      let newFeedURL = URL(string: newFeedURLString)
    else { return nil }

    return newFeedURL
  }

  private var title: String? {
    rssFeed.title ?? rssFeed.iTunes?.iTunesTitle
  }

  private var link: URL? {
    guard let link = rssFeed.link, let url = URL(string: link)
    else { return nil }

    return url
  }

  private var image: URL? {
    guard
      let image = rssFeed.image?.url
        ?? rssFeed.iTunes?.iTunesImage?.attributes?.href,
      let url = URL(string: image)
    else { return nil }

    return url
  }

  private var description: String? {
    rssFeed.description ?? rssFeed.iTunes?.iTunesSummary
  }

  // MARK: - Equatable

  static func == (lhs: PodcastFeed, rhs: PodcastFeed) -> Bool {
    lhs.rssFeed == rhs.rssFeed
  }
}
