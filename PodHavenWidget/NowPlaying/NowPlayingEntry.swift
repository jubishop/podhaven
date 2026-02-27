// Copyright Justin Bishop, 2026

import UIKit
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let episodeTitle: String?
  let podcastTitle: String?
  let durationSeconds: Double
  let playbackStatus: PlaybackStatus
  let artwork: UIImage?

  var isPlaying: Bool { playbackStatus.playing }
  var isLoading: Bool { playbackStatus.loading }

  var durationFormatted: String { durationSeconds.playbackTimeFormat }

  static let empty = NowPlayingEntry(
    date: Date(),
    episodeTitle: nil,
    podcastTitle: nil,
    durationSeconds: 0,
    playbackStatus: .stopped,
    artwork: nil
  )

  static let preview = NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: "Swift Talk",
    durationSeconds: 2460,
    playbackStatus: .playing,
    artwork: nil
  )
}
