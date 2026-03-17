// Copyright Justin Bishop, 2026

import AppIntents
import SwiftUI
import WidgetKit

struct WidgetEpisodeList: View {
  private let imageSize: CGFloat = 56

  let podcastEpisodes: [Episode]

  struct Episode: Identifiable {
    let id: Int64
    let title: String
    let pubDateFormatted: String
    let durationFormatted: String
    let artwork: UIImage?
    let deepLinkURL: URL
  }

  var body: some View {
    TruncatingVStack {
      ForEach(Array(podcastEpisodes.enumerated()), id: \.element.id) { index, episode in
        VStack(spacing: 0) {
          if index > 0 {
            Divider()
              .padding(.leading, imageSize + 4)
              .padding(.trailing, 14)
          }

          episodeRow(episode: episode)
        }
      }
    }
  }

  private func episodeRow(episode: Episode) -> some View {
    HStack(spacing: 8) {
      Link(destination: episode.deepLinkURL) {
        HStack(spacing: 8) {
          SquareImage(
            image: episode.artwork,
            cornerRadius: 4,
            size: imageSize,
            placeholderIcon: .audioPlaceholder
          )

          VStack(alignment: .leading, spacing: 4) {
            Text(episode.title)
              .font(.callout)
              .lineLimit(2, reservesSpace: true)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, alignment: .topLeading)

            HStack {
              CompactMetadataItem(appIcon: .publishDate, value: episode.pubDateFormatted)
              Spacer()
              CompactMetadataItem(appIcon: .duration, value: episode.durationFormatted)
            }
            .font(.caption)
          }
        }
      }

      Button(intent: PlayEpisodeIntent(episodeID: episode.id)) {
        AppIcon.playButton.image
          .font(.callout)
      }
    }
    .padding(.vertical, 4)
  }
}
