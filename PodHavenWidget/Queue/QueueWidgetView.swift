// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

struct QueueWidgetView: View {
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
        WidgetEpisodeList(
          podcastEpisodes: entry.items.map { item in
            WidgetEpisodeList.Episode(
              id: item.id,
              title: item.episodeTitle,
              pubDateFormatted: item.pubDateFormatted,
              durationFormatted: item.durationFormatted,
              artwork: item.artwork,
              deepLinkURL: item.deepLinkURL
            )
          }
        )
      }
    }
    .dynamicTypeSize(.small ... .xxxLarge)
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
