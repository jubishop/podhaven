// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

extension FeedResult {
  var isFailure: Bool {
    if case .failure = self { return true }
    return false
  }

  func isSuccessfulWith(_ expectedFeed: PodcastFeed) -> Bool {
    if case .success(let podcastFeed) = self { return podcastFeed == expectedFeed }
    return false
  }

  func isSuccessfulWith() -> PodcastFeed? {
    if case .success(let podcastFeed) = self { return podcastFeed }
    return nil
  }

  func isSuccessful() -> Bool {
    if case .success = self { return true }
    return false
  }
}
