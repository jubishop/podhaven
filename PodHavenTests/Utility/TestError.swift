// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

enum TestError: Error {
  case assetLoadFailure(PodcastEpisode)
  case waitForValueFailure(String)
  case waitUntilFailure(String)
  case unexpectedCallCount(expected: Int, actual: Int, type: String)
  case unexpectedCall(type: String, calls: [String])
  case fileNotFound(URL)
  case notificationAuthorizationFailed
  case simulatedFailure
}
