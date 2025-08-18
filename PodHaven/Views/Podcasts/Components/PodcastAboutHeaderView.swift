// Copyright Justin Bishop, 2025

import SwiftUI

struct PodcastAboutHeaderView: View {
  @Binding var displayAboutSection: Bool
  let mostRecentEpisodeDate: Date

  var body: some View {
    HStack {
      if displayAboutSection {
        Text("About")
          .font(.headline)
          .fontWeight(.semibold)
      } else {
        HStack(spacing: 4) {
          Image(systemName: "calendar")
            .foregroundColor(.secondary)
            .font(.caption)
          Text(mostRecentEpisodeDate.usShortWithTime)
            .font(.subheadline)
            .fontWeight(.medium)
        }
      }
      Spacer()
      Button(action: {
        withAnimation(.easeInOut(duration: 0.3)) {
          displayAboutSection.toggle()
        }
      }) {
        HStack(spacing: 4) {
          Text(displayAboutSection ? "Hide About" : "Show About")
          Image(systemName: displayAboutSection ? "chevron.up" : "chevron.down")
        }
        .font(.caption)
        .foregroundColor(.accentColor)
      }
    }
  }
}
