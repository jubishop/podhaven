// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct UnsavedPodcast: Savable {
  let feedURL: URL
  var title: String

  init(feedURL: URL, title: String) throws {
    try UnsavedPodcast.validateURL(feedURL)

    self.feedURL = feedURL
    self.title = title
  }

  // MARK: - Validations

  private static func validateURL(_ url: URL) throws {
    guard let scheme = url.scheme, scheme == "https"
    else {
      throw DBError.validationError("feedURL must use https scheme.")
    }
    guard let host = url.host, !host.isEmpty else {
      throw DBError.validationError(
        "feedURL must be an absolute URL with a valid host."
      )
    }
    if url.fragment != nil {
      throw DBError.validationError("feedURL should not contain a fragment.")
    }
  }
}

typealias Podcast = Saved<UnsavedPodcast>
