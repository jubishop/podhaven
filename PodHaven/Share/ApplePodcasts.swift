// Copyright Justin Bishop, 2025

import Foundation

enum ApplePodcasts {
  // MARK: - URL Analysis

  static func isApplePodcastsURL(_ url: URL) -> Bool {
    // https://podcasts.apple.com/us/podcast/podcast-name/id1234567890
    url.scheme == "https" && url.host?.contains("podcasts.apple.com") == true
  }

  static func extractITunesID(from url: URL) throws(ShareError) -> String {
    guard isApplePodcastsURL(url)
    else { throw ShareError.unsupportedURL(url) }

    let pathComponents = url.path.components(separatedBy: "/")
    for component in pathComponents {
      if component.hasPrefix("id"), component.count > 2 {
        let idString = String(component.dropFirst(2))
        if !idString.isEmpty { return idString }
      }
    }

    throw ShareError.noIdentifierFound(url)
  }
}
