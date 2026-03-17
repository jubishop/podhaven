// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

struct PodcastDetailWidgetView: View {
  let entry: PodcastDetailEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if entry.isPlaceholder {
        unconfiguredView
      } else if entry.episodes.isEmpty {
        header
          .padding(.bottom, 6)
        emptyEpisodesView
      } else {
        header
          .padding(.bottom, 6)
        WidgetEpisodeList(podcastEpisodes: entry.episodes)
      }
    }
    .dynamicTypeSize(.small ... .xxxLarge)
  }

  private var header: some View {
    HStack(spacing: 8) {
      SquareImage(
        image: entry.podcastArtwork,
        cornerRadius: 8,
        size: 64,
        placeholderIcon: .showPodcast
      )

      VStack(alignment: .leading, spacing: 4) {
        Text(entry.podcastTitle)
          .font(.subheadline)
          .fontWeight(.semibold)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .topLeading)

        CompactMetadataItem(appIcon: .updated, value: entry.lastUpdatedFormatted)
          .font(.caption)
      }
    }
  }

  private var unconfiguredView: some View {
    VStack(spacing: 8) {
      AppIcon.showPodcast.image
        .font(.largeTitle)
        .foregroundStyle(.quaternary)
      Text("Select a podcast")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyEpisodesView: some View {
    VStack(spacing: 8) {
      AppIcon.episodes.image
        .font(.largeTitle)
        .foregroundStyle(.quaternary)
      Text("No episodes")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#if DEBUG
#Preview("Podcast Detail - Large", as: .systemLarge) {
  PodcastDetailWidget()
} timeline: {
  PodcastDetailEntry.preview
  PodcastDetailEntry.empty
}
#endif
