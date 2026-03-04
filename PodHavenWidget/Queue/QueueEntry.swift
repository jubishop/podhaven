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
        durationFormatted: "41:00",
        artwork: nil
      ),
      QueueEntryItem(
        id: 2,
        episodeTitle: "The Future of AI",
        durationFormatted: "58:30",
        artwork: nil
      ),
      QueueEntryItem(
        id: 3,
        episodeTitle: "Building Better Habits",
        durationFormatted: "22:15",
        artwork: nil
      ),
      QueueEntryItem(
        id: 4,
        episodeTitle: "Deep Work in Practice",
        durationFormatted: "35:45",
        artwork: nil
      ),
      QueueEntryItem(
        id: 5,
        episodeTitle: "Rust vs Swift Performance",
        durationFormatted: "47:20",
        artwork: nil
      ),
      QueueEntryItem(
        id: 6,
        episodeTitle: "Designing for Accessibility",
        durationFormatted: "29:50",
        artwork: nil
      ),
      QueueEntryItem(
        id: 7,
        episodeTitle: "What Makes a Great API",
        durationFormatted: "44:10",
        artwork: nil
      ),
      QueueEntryItem(
        id: 8,
        episodeTitle: "The Art of Debugging",
        durationFormatted: "33:25",
        artwork: nil
      ),
    ],
    totalCount: 12
  )
}
