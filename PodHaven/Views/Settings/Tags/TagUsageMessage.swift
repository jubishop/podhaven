// Copyright Justin Bishop, 2026

import Foundation

enum TagUsageMessage {
  // "2 podcasts and 1 episode"; omits a side whose count is zero.
  static func usage(podcasts: Int, episodes: Int) -> String {
    var parts = [String](capacity: 2)
    if podcasts > 0 {
      parts.append("\(podcasts) \(podcasts == 1 ? "podcast" : "podcasts")")
    }
    if episodes > 0 {
      parts.append("\(episodes) \(episodes == 1 ? "episode" : "episodes")")
    }
    return parts.joined(separator: " and ")
  }
}
