// Copyright Justin Bishop, 2026

import AppIntents
import SwiftUI
import WidgetKit

struct QueueWidgetView: View {
  private let imageSize: CGFloat = 56

  let entry: QueueEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      OptionalLink(url: URL(string: "podhaven://widget/queue")) {
        HStack {
          AppIcon.episodes.label("Up Next")
            .fontWeight(.semibold)
          Spacer()
        }
        .font(.callout)
      }
      .padding(.bottom, 6)

      if entry.items.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: AppIcon.upNext.systemImageName)
            .font(.largeTitle)
            .foregroundStyle(.quaternary)
          Text("Add episodes to your queue")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        TruncatingVStack {
          ForEach(Array(entry.items.enumerated()), id: \.element.id) { index, item in
            VStack(spacing: 0) {
              if index > 0 {
                Divider()
                  .padding(.leading, imageSize + 4)
                  .padding(.trailing, 14)
              }

              queueItemRow(item: item, index: index)
            }
          }
        }
      }
    }
    .dynamicTypeSize(.small ... .xxxLarge)
  }

  private func queueItemRow(item: QueueEntry.QueueEntryItem, index: Int) -> some View {
    HStack(spacing: 8) {
      Link(destination: item.deepLinkURL) {
        HStack(spacing: 8) {
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
        }
      }

      Button(intent: PlayEpisodeIntent(episodeID: item.id)) {
        AppIcon.playButton.image
          .font(.callout)
      }
    }
    .padding(.vertical, 4)
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
