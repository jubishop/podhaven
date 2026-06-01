// Copyright Justin Bishop, 2026

import UIKit
import WidgetKit

struct NowPlayingQueueEntry: TimelineEntry {
  let date: Date
  let episodeTitle: String
  let playbackStatus: PlaybackStatus
  let artwork: UIImage?
  let skipForwardInterval: Int
  let skipBackwardInterval: Int
  let queueItems: [QueueEntry.QueueEntryItem]
  let queueTotalCount: Int

  static let empty = NowPlayingQueueEntry(
    date: Date(),
    episodeTitle: "",
    playbackStatus: .stopped,
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15,
    queueItems: [],
    queueTotalCount: 0
  )

  static let preview = NowPlayingQueueEntry(
    date: Date(),
    episodeTitle: "Understanding Swift Concurrency",
    playbackStatus: .playing,
    artwork: nil,
    skipForwardInterval: 30,
    skipBackwardInterval: 15,
    queueItems: QueueEntry.preview.items,
    queueTotalCount: QueueEntry.preview.totalCount
  )
}
