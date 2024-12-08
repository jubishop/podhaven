// Copyright Justin Bishop, 2024

@preconcurrency import FeedKit
import Foundation

typealias ParseResult = Result<PodcastFeed, FeedError>

struct PodcastFeedItem: Sendable {
  private let rssFeedItem: RSSFeedItem
  fileprivate init(rssFeedItem: RSSFeedItem) {
    self.rssFeedItem = rssFeedItem
  }
}

struct PodcastFeed: Sendable {
  static func parse(_ url: URL) async -> ParseResult {
    guard let data = try? Data(contentsOf: url) else {
      return .failure(.failedLoad(url))
    }
    return await parse(data: data)
  }

  static func parse(data: Data) async -> ParseResult {
    let parser = FeedParser(data: data)
    return await withCheckedContinuation {
      continuation in
      switch parser.parse() {
      case .success(let feed):
        guard let rssFeed = feed.rssFeed else {
          return continuation.resume(returning: .failure(.noRSS))
        }
        continuation.resume(returning: .success(PodcastFeed(rssFeed: rssFeed)))
      case .failure(let error):
        continuation.resume(returning: .failure(.failedParse(error)))
      }
    }
  }

  private let rssFeed: RSSFeed
  private let items: [PodcastFeedItem]

  private init(rssFeed: RSSFeed) {
    self.rssFeed = rssFeed
    self.items = (rssFeed.items ?? [])
      .map { rssFeedItem in PodcastFeedItem(rssFeedItem: rssFeedItem) }
  }

  var feedURL: URL? {
    if let newFeedURLString = rssFeed.iTunes?.iTunesNewFeedURL,
      let newFeedURL = URL(string: newFeedURLString)
    {
      return newFeedURL
    }
    return nil
  }

  var title: String? {
    rssFeed.title ?? rssFeed.iTunes?.iTunesTitle
  }

  var link: URL? {
    guard let link = rssFeed.link, let url = URL(string: link) else {
      return nil
    }
    return url
  }

  var image: URL? {
    guard
      let image = rssFeed.image?.url
        ?? rssFeed.iTunes?.iTunesImage?.attributes?.href,
      let url = URL(string: image)
    else {
      return nil
    }
    return url
  }

  var description: String? {
    rssFeed.description ?? rssFeed.iTunes?.iTunesSummary
  }
}
