// Copyright Justin Bishop, 2026

import Foundation
import UIKit
import WidgetKit

struct QueueEntry: TimelineEntry {
  let date: Date
  let items: [QueueEntryItem]

  private static let queueBaseURL: URL = {
    guard let url = URL(string: "podhaven://widget/queue/") else {
      Assert.fatal("Failed to build widget queue URL")
    }

    return url
  }()

  struct QueueEntryItem: Identifiable {
    let id: Int64
    let episodeTitle: String
    let pubDateFormatted: String
    let durationFormatted: String
    let artwork: UIImage?

    var deepLinkURL: URL {
      QueueEntry.queueBaseURL.appending(path: String(id))
    }
  }

  static let empty = QueueEntry(date: Date(), items: [])

  static let preview = QueueEntry(
    date: Date(),
    items: [
      QueueEntryItem(
        id: 1,
        episodeTitle: "Understanding Swift Concurrency",
        pubDateFormatted: "2/28/26",
        durationFormatted: "41:00",
        artwork: nil
      ),
      QueueEntryItem(
        id: 2,
        episodeTitle: "The Future of AI",
        pubDateFormatted: "2/25/26",
        durationFormatted: "58:30",
        artwork: nil
      ),
      QueueEntryItem(
        id: 3,
        episodeTitle: "Building Better Habits",
        pubDateFormatted: "2/20/26",
        durationFormatted: "22:15",
        artwork: nil
      ),
      QueueEntryItem(
        id: 4,
        episodeTitle: "Deep Work in Practice",
        pubDateFormatted: "2/18/26",
        durationFormatted: "35:45",
        artwork: nil
      ),
      QueueEntryItem(
        id: 5,
        episodeTitle: "Rust vs Swift Performance",
        pubDateFormatted: "2/15/26",
        durationFormatted: "47:20",
        artwork: nil
      ),
    ]
  )
}
