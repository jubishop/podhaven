// Copyright Justin Bishop, 2026

import UIKit
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let episodeTitle: String?
  let podcastTitle: String?
  let durationSeconds: Double
  let currentTimeSeconds: Double
  let isPlaying: Bool
  let artwork: UIImage?

  var progress: Double {
    guard durationSeconds > 0 else { return 0 }
    return min(currentTimeSeconds / durationSeconds, 1.0)
  }

  var remainingFormatted: String {
    let remaining = max(durationSeconds - currentTimeSeconds, 0)
    let minutes = Int(remaining) / 60
    let seconds = Int(remaining) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  var currentTimeFormatted: String {
    let minutes = Int(currentTimeSeconds) / 60
    let seconds = Int(currentTimeSeconds) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  var durationFormatted: String {
    let minutes = Int(durationSeconds) / 60
    let seconds = Int(durationSeconds) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  static let empty = NowPlayingEntry(
    date: Date(),
    episodeTitle: nil,
    podcastTitle: nil,
    durationSeconds: 0,
    currentTimeSeconds: 0,
    isPlaying: false,
    artwork: nil
  )

  static let preview = NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: "Swift Talk",
    durationSeconds: 2460,
    currentTimeSeconds: 1230,
    isPlaying: true,
    artwork: nil
  )
}
