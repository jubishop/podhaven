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
  let skipForwardInterval: Int
  let skipBackwardInterval: Int

  static let empty = NowPlayingEntry(
    date: Date(),
    episodeTitle: nil,
    podcastTitle: nil,
    durationFormatted: "",
    playbackStatus: .stopped,
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15
  )

  static let preview = NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: "Swift Talk",
    durationFormatted: "41:00",
    playbackStatus: .playing,
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15
  )
}
