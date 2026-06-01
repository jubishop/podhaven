// Copyright Justin Bishop, 2026

import AppIntents
import SwiftUI

struct QueueRowView: View {
  let item: QueueEntry.QueueEntryItem
  let imageSize: CGFloat

  var body: some View {
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
