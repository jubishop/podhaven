// Copyright Justin Bishop, 2025

import SwiftUI

struct PodcastListView: View {
  let podcast: any PodcastDisplayable

  var body: some View {
    HStack(spacing: 12) {
      PodLazyImage(url: podcast.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
              AppIcon.noImage.coloredImage
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
          PodcastListView(podcast: unsavedPodcast)
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
