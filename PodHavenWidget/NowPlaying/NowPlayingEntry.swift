// Copyright Justin Bishop, 2026

import UIKit
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let episodeTitle: String?
  let podcastTitle: String?
  let pubDateFormatted: String
  let durationFormatted: String
  let playbackStatus: PlaybackStatus
  let artwork: UIImage?
  let skipForwardInterval: Int
  let skipBackwardInterval: Int

  static let empty = NowPlayingEntry(
    date: Date(),
    episodeTitle: nil,
    podcastTitle: nil,
    pubDateFormatted: "",
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
    pubDateFormatted: "2/28/26",
    durationFormatted: "41:00",
    playbackStatus: .playing,
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15
  )
}
