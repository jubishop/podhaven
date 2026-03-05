// Copyright Justin Bishop, 2026

import UIKit
import WidgetKit

enum TrackControlStyle {
  case seekInterval(forward: Int, backward: Int)
  case skipEpisode
}

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let episodeTitle: String?
  let podcastTitle: String?
  let durationFormatted: String
  let playbackStatus: PlaybackStatus
  let artwork: UIImage?
  let trackControlStyle: TrackControlStyle

  static let empty = NowPlayingEntry(
    date: Date(),
    episodeTitle: nil,
    podcastTitle: nil,
    durationFormatted: "",
    playbackStatus: .stopped,
    artwork: nil,
    trackControlStyle: .skipEpisode
  )

  static let preview = NowPlayingEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    podcastTitle: "Swift Talk",
    durationFormatted: "41:00",
    playbackStatus: .playing,
    artwork: nil,
    trackControlStyle: .seekInterval(forward: 30, backward: 15)
  )
}
