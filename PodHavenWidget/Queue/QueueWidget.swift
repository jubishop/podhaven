// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

struct QueueProvider: TimelineProvider {
  func placeholder(in context: Context) -> QueueEntry {
    .preview
  }

  func getSnapshot(in context: Context, completion: @escaping (QueueEntry) -> Void) {
    WidgetLog.debug("Queue getSnapshot called (isPreview=\(context.isPreview))")
    completion(makeEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<QueueEntry>) -> Void) {
    WidgetLog.debug("Queue getTimeline called (family=\(context.family))")
    let entry = makeEntry()
    let nextUpdate = Date().addingTimeInterval(600)
    let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
    completion(timeline)
  }

  private func makeEntry() -> QueueEntry {
    guard let snapshot = WidgetSnapshotReader.read() else {
      WidgetLog.warning("Queue makeEntry: no snapshot available, returning empty")
      return .empty
    }

    WidgetLog.debug("Queue makeEntry: \(snapshot.queue.count) items")

    let items = snapshot.queue.map { queueItem in
      QueueEntry.QueueEntryItem(
        id: queueItem.episodeID,
        episodeTitle: queueItem.episodeTitle,
        podcastTitle: queueItem.podcastTitle,
        durationFormatted: formatDuration(queueItem.durationSeconds)
      )
    }

    return QueueEntry(date: Date(), items: items)
  }

  private func formatDuration(_ seconds: Double) -> String {
    let totalSeconds = Int(seconds)
    let minutes = totalSeconds / 60
    let secs = totalSeconds % 60
    return String(format: "%d:%02d", minutes, secs)
  }
}

struct QueueWidget: Widget {
  let kind = WidgetConstants.queueKind

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
