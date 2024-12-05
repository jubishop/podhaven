// Copyright Justin Bishop, 2024

import NukeUI
import SwiftUI

struct PodcastView: View {
  @State private var containerWidth: CGFloat = 0

  let podcast: Podcast

  var body: some View {
    VStack {
      Group {
        if let image = podcast.image {
          LazyImage(url: image) { state in
            if let image = state.image {
              image.resizable().aspectRatio(contentMode: .fill)
            } else if state.error != nil {
              Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .foregroundColor(.red)
            } else {
              Color.gray
                .cornerRadius(8)
            }
          }
        } else {
          Color.gray
            .cornerRadius(8)
        }
      }
      .onGeometryChange(for: CGFloat.self) { geometry in
        return geometry.size.width
      } action: { newWidth in
        containerWidth = newWidth
      }
      .frame(height: containerWidth)

      Text(podcast.title)
        .font(.caption)
        .lineLimit(1)
    }
  }
}

struct PodcastsView: View {
  @State private var viewModel = PodcastsViewModel()
  @State private var containerWidth: CGFloat = 0

  private let spacing: CGFloat = 10
  private let numberOfColumns = 3

  init(repository: PodcastRepository = .shared) {
    _viewModel = State(initialValue: PodcastsViewModel(repository: repository))
  }

  var body: some View {
    ScrollView {
      let rows = viewModel.podcasts.chunked(size: numberOfColumns)
      Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
        ForEach(rows, id: \.self) { row in
          GridRow {
            ForEach(row) { podcast in
              PodcastView(podcast: podcast)
            }
          }
        }
      }
      .padding()
    }
    .task {
      await viewModel.observePodcasts()
    }
  }
}

#Preview {
  Preview { PodcastsView(repository: .shared) }
}
