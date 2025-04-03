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
      ZStack {
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
          .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
          } action: { newWidth in
            width = newWidth
          }
          .frame(height: width)
        }

        if viewModel.isSelecting {
          Rectangle()
            .fill(Color.black.opacity(viewModel.isSelected.wrappedValue ? 0.0 : 0.3))
            .cornerRadius(cornerRadius)
            .frame(height: width)

          VStack {
            Spacer()
            HStack {
              Spacer()
              Image(
                systemName: viewModel.isSelected.wrappedValue ? "checkmark.circle.fill" : "circle"
              )
              .foregroundColor(viewModel.isSelected.wrappedValue ? .blue : .white)
              .background(
                Circle()
                  .fill(Color.black.opacity(0.5))
                  .padding(-2)
              )
              .padding(8)
            }
          }
          .frame(height: width)
        }
      }

      Text(viewModel.item.title)
        .font(.caption)
        .lineLimit(1)
    }
  }
}

#Preview {
  @Previewable @State var podcast: Podcast?
  @Previewable @State var invalidPodcast: Podcast?

  LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
    if let podcast = podcast, let invalidPodcast = invalidPodcast {
      ForEach([true, false], id: \.self) { isSelected in
        ForEach([true, false], id: \.self) { isSelecting in
          PodcastGridItem(
            viewModel: PodcastGridItemViewModel(
              isSelected: .constant(isSelected),
              item: podcast,
              isSelecting: isSelecting
            )
          )
          PodcastGridItem(
            viewModel: PodcastGridItemViewModel(
              isSelected: .constant(isSelected),
              item: invalidPodcast,
              isSelecting: isSelecting
            )
          )
        }
      }
    }
  }
  .preview()
  .task {
    do {
      podcast = try await PreviewHelpers.loadPodcast()
      invalidPodcast = try await PreviewHelpers.loadPodcast()
      invalidPodcast?.image = URL(string: "http://nope.com/0.jpg")!
    } catch { fatalError("Couldn't preview podcast thumbnail: \(error)") }
  }
}
