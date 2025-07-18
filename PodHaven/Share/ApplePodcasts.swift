// Copyright Justin Bishop, 2025

import Foundation

// TODO: Only test ShareService as public surface.  This is internal work.
enum ApplePodcasts {
  // MARK: - URL Analysis

  static func isApplePodcastsURL(_ url: URL) -> Bool {
    if url.scheme == "podcasts" {
      return true
    }

    if url.scheme == "https" && url.host?.contains("podcasts.apple.com") == true {
      return true
    }

    return false
  }

  static func extractITunesID(from url: URL) throws(ShareError) -> String {
    guard isApplePodcastsURL(url)
    else { throw ShareError.unsupportedURL(url) }

    // Handle podcasts:// scheme URLs
    if url.scheme == "podcasts" {
      // podcasts://podcasts.apple.com/us/podcast/id1234567890
      let pathComponents = url.path.components(separatedBy: "/")
      for component in pathComponents {
        if component.hasPrefix("id"), component.count > 2 {
          let idString = String(component.dropFirst(2))
          if !idString.isEmpty {
            return idString
          }
        }
      }
    }

    // Handle https://podcasts.apple.com URLs
    if url.scheme == "https" && url.host?.contains("podcasts.apple.com") == true {
      // https://podcasts.apple.com/us/podcast/podcast-name/id1234567890
      let pathComponents = url.path.components(separatedBy: "/")
      for component in pathComponents {
        if component.hasPrefix("id"), component.count > 2 {
          let idString = String(component.dropFirst(2))
          if !idString.isEmpty {
            return idString
          }
        }
      }

      // Also check query parameters for id
      if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let queryItems = components.queryItems
      {
        for item in queryItems {
          if item.name == "id", let value = item.value, !value.isEmpty {
            return value
          }
        }
      }
    }

    throw ShareError.noIdentifierFound(url)
  }
}
