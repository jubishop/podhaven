// Copyright Justin Bishop, 2024

import NukeUI
import SwiftUI

extension Collection {
  func splitIntoRows(size: Int) -> [[Element]] {
    var result: [[Element]] = []
    var currentRow: [Element] = []

    for element in self {
      currentRow.append(element)
      if currentRow.count == size {
        result.append(currentRow)
        currentRow = []
      }
    }

    if !currentRow.isEmpty {
      result.append(currentRow)
    }

    return result
  }
}

struct PodcastView: View {
  let podcast: Podcast

  var body: some View {
    VStack {
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
      let rows = viewModel.podcasts.splitIntoRows(size: numberOfColumns)
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
