// Copyright Justin Bishop, 2025

import Foundation

enum SharedURLType {
  case applePodcasts
  case unsupported
}

extension SharedURLType {
  static func urlType(for url: URL) -> SharedURLType {
    if ApplePodcasts.isApplePodcastsURL(url) {
      return .applePodcasts
    }

    return .unsupported
  }
}
