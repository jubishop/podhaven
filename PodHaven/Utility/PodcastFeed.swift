// Copyright Justin Bishop, 2024

@preconcurrency import FeedKit
import Foundation

actor PodcastFeed: Sendable {
  static func parse(_ url: URL) async -> Result<PodcastFeed, FeedError> {
    guard let data = try? Data(contentsOf: url) else {
      return .failure(.failedLoad(url))
    }
    return await parse(data: data, from: url)
  }

  static func parse(data: Data, from url: URL) async -> Result<
    PodcastFeed, FeedError
  > {
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

  let url: URL
  private let rssFeed: RSSFeed

  private init(url: URL, rssFeed: RSSFeed) {
    self.url = url
    self.rssFeed = rssFeed
  }

  var title: String {
    rssFeed.title ?? "Unknown Title"
  }
}
