// Copyright Justin Bishop, 2024

import GRDB
import NukeUI
import SwiftUI

struct NoImageThumbnail: View {
  @Binding var width: CGFloat
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
  @State private var width: CGFloat = 0

  let podcast: Podcast

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
              NoImageThumbnail(width: $width, cornerRadius: cornerRadius)
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
          NoImageThumbnail(width: $width, cornerRadius: cornerRadius)
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

struct PodcastsView: View {
  @State private var viewModel = PodcastsViewModel()

  private let numberOfColumns = 3

  init(repository: PodcastRepository = .shared) {
    _viewModel = State(initialValue: PodcastsViewModel(repository: repository))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        let rows = viewModel.podcasts.chunked(size: numberOfColumns)
        Grid {
          ForEach(rows, id: \.self) { row in
            GridRow {
              ForEach(row) { podcast in
                PodcastThumbnail(podcast: podcast)
              }
            }
          }
        }
        .padding()
      }
    }
    .task {
      await viewModel.observePodcasts()
    }
  }
}

#Preview {
  struct PodcastsViewPreview: View {
    @State private var repository: PodcastRepository = .shared

    var body: some View {
      PodcastsView()
        .task {
          let weedsPodcast = try? await repository.db.read { db in
            try? Podcast.filter(Column("title") == "Explain It to Me")
              .fetchOne(db)
          }
          if var weedsPodcast = weedsPodcast {
            weedsPodcast.image = nil
            try? repository.update(weedsPodcast)
          }
        }
    }
  }
  return PodcastsViewPreview()
}
