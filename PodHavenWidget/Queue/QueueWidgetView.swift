// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

struct QueueWidgetView: View {
  let entry: QueueEntry

  @Environment(\.widgetFamily) var family

  var body: some View {
    if entry.items.isEmpty {
      emptyState
    } else {
      queueList
    }
  }

  // MARK: - Queue List

  private var queueList: some View {
    VStack(alignment: .leading, spacing: 0) {
      headerRow

      let itemCount = family == .systemLarge ? 5 : 3
      let visibleItems = Array(entry.items.prefix(itemCount))

      ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
        if index > 0 {
          Divider()
            .padding(.leading, 28)
        }

        queueItemRow(item: item, index: index)
      }

      if entry.totalCount > itemCount {
        Spacer(minLength: 0)
        Text("+\(entry.totalCount - itemCount) more")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
      } else {
        Spacer(minLength: 0)
      }
    }
  }

  private var headerRow: some View {
    HStack {
      Image(systemName: "list.bullet")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Up Next")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.bottom, 6)
  }

  private func queueItemRow(item: QueueEntry.QueueEntryItem, index: Int) -> some View {
    Link(destination: item.deepLinkURL) {
      HStack(spacing: 8) {
        Text("\(index + 1)")
          .font(.caption2)
          .fontWeight(.medium)
          .foregroundStyle(.secondary)
          .frame(width: 18)

        VStack(alignment: .leading, spacing: 1) {
          Text(item.episodeTitle)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .foregroundStyle(.primary)

          Text(item.podcastTitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer()

        Text(item.durationFormatted)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "list.bullet")
        .font(.title2)
        .foregroundStyle(.secondary)
      Text("Queue Empty")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Add episodes to your queue")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
