// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

typealias PodcastGridItemViewModel = SelectableListItemModel<Podcast>

struct PodcastGridItem: View {
  @State private var width: CGFloat = 0

  private let viewModel: PodcastGridItemViewModel
  private let cornerRadius: CGFloat = 8

  init(viewModel: PodcastGridItemViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      Group {
        LazyImage(url: viewModel.item.image) { state in
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

      Text(viewModel.item.title)
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
      PodcastGridItem(viewModel: PodcastGridItemViewModel(
        isSelected: .constant(false),
        item: podcast,
        isSelecting: false
      )).padding()
    }
    if let invalidPodcast = invalidPodcast {
      PodcastGridItem(viewModel: PodcastGridItemViewModel(
        isSelected: .constant(false),
        item: invalidPodcast,
        isSelecting: false
      )).padding()
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
