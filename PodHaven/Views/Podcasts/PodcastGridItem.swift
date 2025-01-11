// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct PodcastGridItem: View {
  @State private var width: CGFloat = 0

  private let podcast: Podcast
  private let cornerRadius: CGFloat = 8

  init(podcast: Podcast) {
    self.podcast = podcast
  }

  var body: some View {
    VStack {
      Group {
        LazyImage(url: podcast.image) { state in
          if let image = state.image {
            image
              .resizable()
              .cornerRadius(cornerRadius)
          } else {
            ZStack {
              Color.gray
                .cornerRadius(cornerRadius)
              VStack {
                Image(systemName: "photo")
                  .resizable()
                  .scaledToFit()
                  .frame(width: width / 2, height: width / 2)
                  .foregroundColor(.white.opacity(0.8))
                Text("No Image")
                  .font(.caption)
                  .foregroundColor(.white.opacity(0.8))
              }
            }
          }
        }
      }
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.size.width
      } action: { newWidth in
        width = newWidth
      }
      .frame(height: width)

      Text(podcast.title)
        .font(.caption)
        .lineLimit(1)
    }
  }
}

#Preview {
  @Previewable @State var podcast: Podcast?
  @Previewable @State var invalidPodcast: Podcast?

  VStack {
    if let podcast = podcast {
      PodcastGridItem(podcast: podcast).padding()
    }
    if let invalidPodcast = invalidPodcast {
      PodcastGridItem(podcast: invalidPodcast).padding()
    }
  }
  .padding()
  .preview()
  .task {
    do {
      podcast = try await PreviewHelpers.loadPodcast()
      invalidPodcast = try await PreviewHelpers.loadPodcast()
      invalidPodcast?.image = URL(string: "http://nope.com/0.jpg")!
    } catch { fatalError("Couldn't preview podcast thumbnail: \(error)") }
  }
}
