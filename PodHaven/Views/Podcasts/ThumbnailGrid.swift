// Copyright Justin Bishop, 2024

import GRDB
import NukeUI
import SwiftUI

struct NoImageThumbnail: View {
  let width: CGFloat
  let cornerRadius: CGFloat

  var body: some View {
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

struct PodcastThumbnail: View {
  let podcast: Podcast

  @State private var width: CGFloat = 0
  private let cornerRadius: CGFloat = 8

  var body: some View {
    VStack {
      Group {
        if let image = podcast.image {
          LazyImage(url: image) { state in
            if let image = state.image {
              image
                .resizable()
                .cornerRadius(cornerRadius)
            } else if state.error != nil {
              NoImageThumbnail(width: width, cornerRadius: cornerRadius)
            } else {
              ZStack {
                Color.gray
                  .cornerRadius(cornerRadius)
                Image(systemName: "photo")
                  .resizable()
                  .scaledToFit()
                  .frame(width: width / 2, height: width / 2)
                  .foregroundColor(.white.opacity(0.8))
              }
            }
          }
        } else {
          NoImageThumbnail(width: width, cornerRadius: cornerRadius)
        }
      }
      .onGeometryChange(for: CGFloat.self) { geometry in
        return geometry.size.width
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

struct ThumbnailGrid: View {
  let podcasts: [Podcast]
  private let numberOfColumns = 3

  var body: some View {
    let rows = podcasts.chunked(size: numberOfColumns)
    Grid {
      ForEach(rows, id: \.self) { row in
        GridRow {
          ForEach(row) { podcast in
            NavigationLink(
              value: podcast,
              label: { PodcastThumbnail(podcast: podcast) }
            )
          }
        }
      }
    }
  }
}

#Preview {
  @Previewable @State var podcasts: [Podcast] = []

  Preview {
    ThumbnailGrid(podcasts: podcasts)
      .task {
        do {
          var fetchedPodcasts = try PodcastRepository.shared.db.read { db in
            try Podcast.fetchAll(db)
          }
          if fetchedPodcasts.count > 2 {
            fetchedPodcasts[0].image = nil
            fetchedPodcasts[1].image = URL(string: "http://nope.com/0.jpg")!
          }
          podcasts = Array(fetchedPodcasts.prefix(12))
        } catch {
          print(error.localizedDescription)
        }
      }
  }
}
