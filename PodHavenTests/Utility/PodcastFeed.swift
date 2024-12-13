// Copyright Justin Bishop, 2024

import Foundation

@testable import PodHaven

extension ParseResult {
  var isUnparseable: Bool {
    if case .failure(.failedParse) = self {
      return true
    }
    return false
  }

  func isSuccessfulWith(_ expectedFeed: PodcastFeed) -> Bool {
    if case .success(let podcastFeed) = self {
      return podcastFeed == expectedFeed
    }
    return false
  }

  func isSuccessfulWith() -> PodcastFeed? {
    if case .success(let podcastFeed) = self {
      return podcastFeed
    }
    return nil
  }

  func isSuccessful() -> Bool {
    if case .success = self {
      return true
    }
    return false
  }
}
