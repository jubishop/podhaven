// Copyright Justin Bishop, 2026

import WidgetKit

struct LockScreenNowPlayingEntry: TimelineEntry {
  let date: Date
  let episodeTitle: String
  let podcastTitle: String
  let playbackStatus: PlaybackStatus

  static let empty = LockScreenNowPlayingEntry(
    date: Date(),
    episodeTitle: "",
    podcastTitle: "",
    playbackStatus: .stopped
  )

  static let preview = LockScreenNowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: "Swift Talk",
    playbackStatus: .playing
  )
}
