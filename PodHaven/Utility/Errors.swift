// Copyright Justin Bishop, 2024

import Foundation

enum DBError: Error, LocalizedError, Sendable {
  case episodeNotFound(Int64)
  case seriesNotFound(Int64)
  case podcastEpisodeNotFound(Int64)

  var errorDescription: String {
    switch self {
    case .episodeNotFound(let id):
      return "Episode with ID: \(id) could not be found."
    case .seriesNotFound(let id):
      return "PodcastSeries with Podcast ID: \(id) could not be found."
    case .podcastEpisodeNotFound(let id):
      return "PodcastEpisode with Podcast ID: \(id) could not be found."
    }
  }
}

enum PlaybackError: Error, LocalizedError, Sendable {
  case notPlayable(Episode)
  case noURL(Episode)
  case notActive
  case noMetadata(Episode)

  var errorDescription: String {
    switch self {
    case .notPlayable(let episode):
      return "The media for: \(episode.toString) cannot be played."
    case .noURL(let episode):
      return "The episode: \(episode.toString) has no URL."
    case .notActive:
      return "The session could not be marked active."
    case .noMetadata(let episode):
      return "Metadata for the episode: \(episode.toString) can't be loaded."
    }
  }
}

enum DownloadError: Error, LocalizedError, Sendable {
  case invalidResponse
  case invalidStatusCode(Int)
  case networkError(String)
  case cancelled

  var errorDescription: String {
    switch self {
    case .invalidResponse:
      return "Received an invalid response from the server."
    case .invalidStatusCode(let statusCode):
      return "Received HTTP status code \(statusCode)."
    case .networkError(let message):
      return "A network error occurred: \"\(message)\""
    case .cancelled:
      return "The download was cancelled."
    }
  }
}

enum FeedError: Error, LocalizedError, Sendable {
  case failedLoad(URL)
  case failedParse(Error)
  case failedConversion(String)
  case cancelled
  case noRSS

  var errorDescription: String {
    switch self {
    case .failedLoad(let url):
      return "Failed to load URL: \(url)"
    case .failedParse(let error):
      return "Failed to parse RSS feed: \"\(error)\""
    case .failedConversion(let message):
      return "Failed feed conversion: \"\(message)\""
    case .noRSS:
      return "No RSS feed found."
    case .cancelled:
      return "The feed download was cancelled."
    }
  }
}
