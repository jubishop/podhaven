// Copyright Justin Bishop, 2026

import Foundation
import UIKit
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
    let artwork: UIImage?

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
        durationFormatted: "41:00",
        artwork: nil
      ),
      QueueEntryItem(
        id: 2,
        episodeTitle: "The Future of AI",
        podcastTitle: "Tech Matters",
        durationFormatted: "58:30",
        artwork: nil
      ),
      QueueEntryItem(
        id: 3,
        episodeTitle: "Building Better Habits",
        podcastTitle: "The Daily",
        durationFormatted: "22:15",
        artwork: nil
      ),
      QueueEntryItem(
        id: 4,
        episodeTitle: "Deep Work in Practice",
        podcastTitle: "Focus Mode",
        durationFormatted: "35:45",
        artwork: nil
      ),
      QueueEntryItem(
        id: 5,
        episodeTitle: "Rust vs Swift Performance",
        podcastTitle: "Systems Programming",
        durationFormatted: "47:20",
        artwork: nil
      ),
      QueueEntryItem(
        id: 6,
        episodeTitle: "Designing for Accessibility",
        podcastTitle: "UI Unpacked",
        durationFormatted: "29:50",
        artwork: nil
      ),
      QueueEntryItem(
        id: 7,
        episodeTitle: "What Makes a Great API",
        podcastTitle: "Backend Bytes",
        durationFormatted: "44:10",
        artwork: nil
      ),
      QueueEntryItem(
        id: 8,
        episodeTitle: "The Art of Debugging",
        podcastTitle: "Code Stories",
        durationFormatted: "33:25",
        artwork: nil
      ),
    ],
    totalCount: 12
  )
}
