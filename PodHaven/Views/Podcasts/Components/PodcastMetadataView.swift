// Copyright Justin Bishop, 2025

import SwiftUI

struct PodcastMetadataView: View {
  let mostRecentEpisodeDate: Date
  let episodeCount: Int

  var body: some View {
    HStack {
      metadataItem(
        icon: "calendar",
        label: "Updated",
        value: mostRecentEpisodeDate.usShortWithTime
      )

      Spacer()

      metadataItem(
        icon: "list.bullet",
        label: "Episodes",
        value: "\(episodeCount)"
      )
    }
  }

  private func metadataItem(icon: String, label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .foregroundColor(.secondary)
          .font(.caption)
        Text(label)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Text(value)
        .font(.subheadline)
        .fontWeight(.medium)
    }
  }
}
