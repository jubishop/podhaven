// Copyright Justin Bishop, 2026

import Logging
import SwiftUI
import WidgetKit

struct QueueProvider: TimelineProvider {
  private static let log = Logger(label: "PodHavenWidget/Queue")

  func placeholder(in context: Context) -> QueueEntry {
    .preview
  }

  func getSnapshot(in context: Context, completion: @escaping (QueueEntry) -> Void) {
    Self.log.debug("Queue getSnapshot called (isPreview=\(context.isPreview))")
    completion(makeEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<QueueEntry>) -> Void) {
    Self.log.debug("Queue getTimeline called (family=\(context.family))")
    let entry = makeEntry()
    let nextUpdate = Date().addingTimeInterval(600)
    let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
    completion(timeline)
  }

  private func makeEntry() -> QueueEntry {
    guard let snapshot = WidgetSnapshotReader.read() else {
      Self.log.warning("Queue makeEntry: no snapshot available, returning empty")
      return .empty
    }

    Self.log.debug("Queue makeEntry: \(snapshot.queue.count) items")

    let items = snapshot.queue.map { queueItem in
      QueueEntry.QueueEntryItem(
        id: queueItem.episodeID,
        episodeTitle: queueItem.episodeTitle,
        podcastTitle: queueItem.podcastTitle,
        durationFormatted: queueItem.durationSeconds.playbackTimeFormat
      )
    }

    return QueueEntry(date: Date(), items: items, totalCount: snapshot.queueTotalCount)
  }
}

struct QueueWidget: Widget {
  let kind = WidgetInfo.queueKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QueueProvider()) { entry in
      QueueWidgetView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Up Next")
    .description("See what's coming up in your queue.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}
