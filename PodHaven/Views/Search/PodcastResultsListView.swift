// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct PodcastResultsListView: View {
  let podcast: UnsavedPodcast
  let searchedText: String

  var body: some View {
    HStack(spacing: 12) {
      LazyImage(url: podcast.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
              Image(systemName: "photo")
                .foregroundColor(.white.opacity(0.8))
                .font(.caption)
            )
        }
      }
      .frame(width: 60, height: 60)
      .clipped()
      .cornerRadius(8)

      VStack(alignment: .leading, spacing: 4) {
        Text(podcast.title)
          .font(.headline)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        if !podcast.description.isEmpty {
          Text(podcast.description)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Spacer()

      Image(systemName: "chevron.right")
        .foregroundColor(.secondary)
        .font(.caption)
    }
    .padding(.vertical, 4)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var unsavedPodcast: UnsavedPodcast?

  NavigationStack {
    List {
      if let unsavedPodcast {
        NavigationLink(destination: Text("Detail View")) {
          PodcastResultsListView(
            podcast: unsavedPodcast,
            searchedText: "test search"
          )
        }
      }
    }
  }
  .preview()
  .task {
    unsavedPodcast = try? await PreviewHelpers.loadUnsavedPodcast()
  }
}
#endif
