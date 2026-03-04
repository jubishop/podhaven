// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

struct QueueWidgetView: View {
  let entry: QueueEntry

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

      TruncatingVStack {
        ForEach(Array(entry.items.enumerated()), id: \.element.id) { index, item in
          VStack(spacing: 0) {
            if index > 0 {
              Divider()
                .padding(.leading, Self.artworkSize + 8)
            }
            queueItemRow(item: item, index: index)
          }
        }

        Link(destination: URL(string: "podhaven://widget/queue")!) {
          Text("View Full Queue")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .layoutValue(key: TruncatingRoleKey.self, value: .overflow)
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

  private static let artworkSize: CGFloat = 28

  private func queueItemRow(item: QueueEntry.QueueEntryItem, index: Int) -> some View {
    Link(destination: item.deepLinkURL) {
      HStack(spacing: 8) {
        SquareImage(
          image: item.artwork,
          cornerRadius: 4,
          size: Self.artworkSize,
          placeholderIcon: .audioPlaceholder
        )

        Text(item.episodeTitle)
          .font(.caption)
          .fontWeight(.medium)
          .lineLimit(2, reservesSpace: true)
          .foregroundStyle(.primary)

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
    Link(destination: URL(string: "podhaven://widget/queue")!) {
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
}

#if DEBUG
#Preview("Queue - Medium", as: .systemMedium) {
  QueueWidget()
} timeline: {
  QueueEntry.preview
  QueueEntry.empty
}

#Preview("Queue - Large", as: .systemLarge) {
  QueueWidget()
} timeline: {
  QueueEntry.preview
  QueueEntry.empty
}
#endif
