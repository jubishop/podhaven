// Copyright Justin Bishop, 2025

import Foundation

enum SharedURLType {
  case applePodcasts
  case unsupported
}

extension SharedURLType {
  static func urlType(for url: URL) -> SharedURLType {
    if ApplePodcastsURLParser.isApplePodcastsURL(url) {
      return .applePodcasts
    }
    
    // Future: Add other URL types here (Spotify, RSS feeds, etc.)
    
    return .unsupported
  }
}