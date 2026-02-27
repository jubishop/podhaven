// Copyright Justin Bishop, 2026

import UIKit
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let episodeTitle: String?
  let podcastTitle: String?
  let durationFormatted: String
  let playbackStatus: PlaybackStatus
  let artwork: UIImage?

  var isPlaying: Bool { playbackStatus.playing }
  var isLoading: Bool { playbackStatus.loading }

  static let empty = NowPlayingEntry(
    date: Date(),
    episodeTitle: nil,
    podcastTitle: nil,
    durationFormatted: "",
    playbackStatus: .stopped,
    artwork: nil
  )

  static let preview = NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: "Swift Talk",
    durationFormatted: "41:00",
    playbackStatus: .playing,
    artwork: nil
  )
}
