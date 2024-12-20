// Copyright Justin Bishop, 2024

@preconcurrency import FeedKit
import Foundation

typealias ParseResult = Result<PodcastFeed, FeedError>

struct PodcastFeedItem: Sendable {
  let guid: String

  private let rssFeedItem: RSSFeedItem

  fileprivate init(rssFeedItem: RSSFeedItem) throws {
    guard let feedItemGUID = rssFeedItem.guid, let guid = feedItemGUID.value
    else { throw FeedError.failedParse("PodcastFeedItem requires a GUID") }
    self.rssFeedItem = rssFeedItem
    self.guid = guid
  }

  func toUnsavedEpisode(mergingExisting existingEpisode: Episode? = nil)
    -> UnsavedEpisode
  {
    guard existingEpisode?.guid == nil || existingEpisode?.guid == guid else {
      fatalError("Merging two episodes with different guids?")
    }
    return UnsavedEpisode(
      guid: guid,
      podcastId: existingEpisode?.podcastId,
      media: media ?? existingEpisode?.media,
      currentTime: existingEpisode?.currentTime,
      pubDate: pubDate ?? existingEpisode?.pubDate,
      title: title ?? existingEpisode?.title,
      description: description ?? existingEpisode?.description,
      link: link ?? existingEpisode?.link,
      image: image ?? existingEpisode?.image
    )
  }

  func toEpisode(mergingExisting existingEpisode: Episode) -> Episode {
    Episode(
      id: existingEpisode.id,
      from: toUnsavedEpisode(mergingExisting: existingEpisode)
    )
  }

  var media: URL? {
    guard let urlString = rssFeedItem.enclosure?.attributes?.url,
      let url = URL(string: urlString)
    else { return nil }
    return url
  }

  var pubDate: Date? {
    rssFeedItem.pubDate
  }

  var title: String? {
    rssFeedItem.title ?? rssFeedItem.iTunes?.iTunesTitle
  }

  var description: String? {
    rssFeedItem.description ?? rssFeedItem.iTunes?.iTunesSummary
  }

  var link: URL? {
    guard let urlString = rssFeedItem.link, let url = URL(string: urlString)
    else { return nil }
    return url
  }

  var image: URL? {
    guard let urlString = rssFeedItem.iTunes?.iTunesImage?.attributes?.href,
      let url = URL(string: urlString)
    else { return nil }
    return url
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
    return await withCheckedContinuation {
      continuation in
      switch parser.parse() {
      case .success(let feed):
        guard let rssFeed = feed.rssFeed
        else { return continuation.resume(returning: .failure(.noRSS)) }
        continuation.resume(returning: .success(PodcastFeed(rssFeed: rssFeed)))
      case .failure(let error):
        continuation.resume(
          returning: .failure(.failedParse(String(describing: error)))
        )
      }
    }
  }

  // MARK: - Instance Definition

  let items: [PodcastFeedItem]

  private let rssFeed: RSSFeed

  private init(rssFeed: RSSFeed) {
    self.rssFeed = rssFeed
    self.items = (rssFeed.items ?? [])
      .compactMap { rssFeedItem in
        try? PodcastFeedItem(rssFeedItem: rssFeedItem)
      }
  }

  func toUnsavedPodcast(mergingExisting existingPodcast: Podcast)
    -> UnsavedPodcast?
  {
    try? UnsavedPodcast(
      feedURL: feedURL ?? existingPodcast.feedURL,
      title: title ?? existingPodcast.title,
      link: link ?? existingPodcast.link,
      image: image ?? existingPodcast.image,
      description: description ?? existingPodcast.description
    )
  }

  func toUnsavedPodcast(oldFeedURL: URL, oldTitle: String) -> UnsavedPodcast? {
    try? toUnsavedPodcast(
      mergingExisting: Podcast(
        from: UnsavedPodcast(feedURL: oldFeedURL, title: oldTitle)
      )
    )
  }

  func toPodcast(mergingExisting existingPodcast: Podcast) -> Podcast? {
    guard
      let unsavedPodcast = toUnsavedPodcast(mergingExisting: existingPodcast)
    else { return nil }
    return Podcast(id: existingPodcast.id, from: unsavedPodcast)
  }

  var feedURL: URL? {
    guard let newFeedURLString = rssFeed.iTunes?.iTunesNewFeedURL,
      let newFeedURL = URL(string: newFeedURLString)
    else { return nil }
    return newFeedURL
  }

  var title: String? {
    rssFeed.title ?? rssFeed.iTunes?.iTunesTitle
  }

  var link: URL? {
    guard let link = rssFeed.link, let url = URL(string: link)
    else { return nil }
    return url
  }

  var image: URL? {
    guard
      let image = rssFeed.image?.url
        ?? rssFeed.iTunes?.iTunesImage?.attributes?.href,
      let url = URL(string: image)
    else { return nil }
    return url
  }

  var description: String? {
    rssFeed.description ?? rssFeed.iTunes?.iTunesSummary
  }

  // MARK: - Equatable

  static func == (lhs: PodcastFeed, rhs: PodcastFeed) -> Bool {
    lhs.rssFeed == rhs.rssFeed
  }
}
