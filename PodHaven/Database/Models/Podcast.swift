// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct UnsavedPodcast: Savable {
  var feedURL: URL
  var title: String
  var link: URL?
  var image: URL?
  var description: String?

  init(feedURL: URL, title: String, link: URL? = nil, image: URL? = nil, description: String? = nil) throws
  {
    self.feedURL = try UnsavedPodcast.convertToValidURL(feedURL)
    self.title = title
    self.link = link
    self.image = image
    self.description = description
  }

  // MARK: - Validations

  public static func convertToValidURL(_ url: URL) throws -> URL {
    guard
      var components = URLComponents(
        url: url,
        resolvingAgainstBaseURL: false
      )
    else {
      throw DatabaseError(
        resultCode: .SQLITE_ERROR,
        message: "URL: \(url) is invalid."
      )
    }
    if components.scheme == "http" {
      components.scheme = "https"
    }
    components.fragment = nil
    guard let url = components.url else {
      throw DatabaseError(
        resultCode: .SQLITE_ERROR,
        message: "URL: \(url) is invalid."
      )
    }
    try validateURL(url)
    return url
  }

  private static func validateURL(_ url: URL) throws {
    guard let scheme = url.scheme, scheme == "https"
    else {
      throw DatabaseError(
        resultCode: .SQLITE_ERROR,
        message: "URL: \(url) must use https scheme."
      )
    }
    guard let host = url.host, !host.isEmpty else {
      throw DatabaseError(
        resultCode: .SQLITE_ERROR,
        message:
          "URL: \(url) must be an absolute URL with a valid host."
      )
    }
    guard url.fragment == nil else {
      throw DatabaseError(
        resultCode: .SQLITE_ERROR,
        message:
          "URL: \(url) should not contain a fragment."
      )
    }
  }
}

typealias Podcast = Saved<UnsavedPodcast>
