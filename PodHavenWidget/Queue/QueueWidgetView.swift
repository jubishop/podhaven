// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

struct QueueWidgetView: View {
  private let imageSize: CGFloat = 56

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
            queueItemRow(item: item, index: index)

            Divider()
              .padding(.leading, imageSize + 4)
              .padding(.trailing, 14)
          }
        }
      }
    }
  }

  private var headerRow: some View {
    Link(destination: URL(string: "podhaven://widget/queue")!) {
      HStack {
        AppIcon.episodes.rawImage
        Text("Up Next")
          .fontWeight(.semibold)
        Spacer()
      }
      .font(.callout)
      .foregroundStyle(.tint)
    }
    .padding(.bottom, 6)
  }

  private func queueItemRow(item: QueueEntry.QueueEntryItem, index: Int) -> some View {
    Link(destination: item.deepLinkURL) {
      HStack(spacing: 4) {
        SquareImage(
          image: item.artwork,
          cornerRadius: 4,
          size: imageSize,
          placeholderIcon: .audioPlaceholder
        )

        VStack(alignment: .leading, spacing: 4) {
          Text(item.episodeTitle)
            .font(.callout)
            .lineLimit(2, reservesSpace: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)

          HStack {
            CompactMetadataItem(appIcon: .publishDate, value: item.pubDateFormatted)
            Spacer()
            CompactMetadataItem(appIcon: .duration, value: item.durationFormatted)
          }
          .font(.caption)
        }

        Image(systemName: "chevron.right")
          .font(.caption)
          .fontWeight(.semibold)
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
#Preview("Queue - Large", as: .systemLarge) {
  QueueWidget()
} timeline: {
  QueueEntry.preview
  QueueEntry.empty
}
#endif
