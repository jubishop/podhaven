// Copyright Justin Bishop, 2026

import Foundation
import WidgetKit

struct QueueEntry: TimelineEntry {
  let date: Date
  let items: [QueueEntryItem]
  let totalCount: Int

  private static let queueBaseURL = URL(string: "podhaven://widget/queue/")!

  struct QueueEntryItem: Identifiable {
    let id: Int64
    let episodeTitle: String
    let podcastTitle: String
    let durationFormatted: String

    var deepLinkURL: URL {
      QueueEntry.queueBaseURL.appending(path: String(id))
    }
  }

  static let empty = QueueEntry(date: Date(), items: [], totalCount: 0)

  static let preview = QueueEntry(
    date: Date(),
    items: [
      QueueEntryItem(
        id: 1,
        episodeTitle: "Understanding Swift Concurrency",
        podcastTitle: "Swift Talk",
        durationFormatted: "41:00"
      ),
      QueueEntryItem(
        id: 2,
        episodeTitle: "The Future of AI",
        podcastTitle: "Tech Matters",
        durationFormatted: "58:30"
      ),
      QueueEntryItem(
        id: 3,
        episodeTitle: "Building Better Habits",
        podcastTitle: "The Daily",
        durationFormatted: "22:15"
      ),
      QueueEntryItem(
        id: 4,
        episodeTitle: "Deep Work in Practice",
        podcastTitle: "Focus Mode",
        durationFormatted: "35:45"
      ),
      QueueEntryItem(
        id: 5,
        episodeTitle: "Rust vs Swift Performance",
        podcastTitle: "Systems Programming",
        durationFormatted: "47:20"
      ),
    ],
    totalCount: 8
  )
}
