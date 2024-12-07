// Copyright Justin Bishop, 2024

@preconcurrency import FeedKit
import Foundation

typealias ParseResult = Result<PodcastFeed, FeedError>

struct PodcastFeed: Sendable {
  static func parse(_ url: URL) async -> ParseResult {
    guard let data = try? Data(contentsOf: url) else {
      return .failure(.failedLoad(url))
    }
    return await parse(data: data, from: url)
  }

  static func parse(data: Data, from url: URL) async -> ParseResult {
    let parser = FeedParser(data: data)
    return await withCheckedContinuation {
      continuation in
      switch parser.parse() {
      case .success(let feed):
        guard let rssFeed = feed.rssFeed else {
          return continuation.resume(returning: .failure(.noRSS))
        }
        let podcastFeed = PodcastFeed(url: url, rssFeed: rssFeed)
        continuation.resume(returning: .success(podcastFeed))
      case .failure(let error):
        continuation.resume(returning: .failure(.failedParse(error)))
      }
    }
  }

  private let url: URL
  private let rssFeed: RSSFeed

  private init(url: URL, rssFeed: RSSFeed) {
    self.url = url
    self.rssFeed = rssFeed
  }

  var feedURL: URL {
    if let newFeedURLString = rssFeed.iTunes?.iTunesNewFeedURL,
      let newFeedURL = URL(string: newFeedURLString)
    {
      return newFeedURL
    }
    return url
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
