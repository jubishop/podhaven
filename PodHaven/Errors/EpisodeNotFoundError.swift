// Copyright Justin Bishop, 2026

import Foundation

struct EpisodeNotFoundError: Error, LocalizedError, Sendable {
  let episodeID: Episode.ID

  var errorDescription: String? {
    "This episode is no longer available."
  }
}
