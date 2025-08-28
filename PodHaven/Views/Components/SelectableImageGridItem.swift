// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct SelectableImageGridItem<Item: Gridable>: View {
  @Binding var size: CGFloat

  private let viewModel: SelectableListItemModel<Item>
  private let cornerRadius: CGFloat = 8

  init(viewModel: SelectableListItemModel<Item>, size: Binding<CGFloat>) {
    self.viewModel = viewModel
    self._size = size
  }

  var body: some View {
    VStack {
      ZStack {
        ImageGridItem(image: viewModel.item.image, size: $size, cornerRadius: cornerRadius)

        if viewModel.isSelecting {
          Rectangle()
            .fill(Color.black.opacity(viewModel.isSelected.wrappedValue ? 0.0 : 0.5))
            .cornerRadius(cornerRadius)
            .frame(height: size)

          VStack {
            Spacer()
            HStack {
              Spacer()
              Button(
                action: {
                  viewModel.isSelected.wrappedValue.toggle()
                },
                label: {
                  (viewModel.isSelected.wrappedValue 
                    ? AppLabel.selectionFilled 
                    : AppLabel.selectionEmpty).image
                  .font(.system(size: 24))
                  .foregroundColor(viewModel.isSelected.wrappedValue ? .blue : .white)
                  .background(
                    Circle()
                      .fill(Color.black.opacity(0.5))
                      .padding(-3)
                  )
                }
              )
              .padding(8)
            }
          }
          .frame(height: size)
        }
      }

      Text(viewModel.item.title)
        .font(.caption)
        .lineLimit(1)
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var podcast: Podcast?
  @Previewable @State var invalidPodcast: Podcast?
  @Previewable @State var gridItemSize: CGFloat = 100

  LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
    if let podcast = podcast, let invalidPodcast = invalidPodcast {
      ForEach([true, false], id: \.self) { isSelected in
        ForEach([true, false], id: \.self) { isSelecting in
          SelectableImageGridItem<Podcast>(
            viewModel: SelectableListItemModel(
              isSelected: .constant(isSelected),
              item: podcast,
              isSelecting: isSelecting
            ),
            size: $gridItemSize
          )
          SelectableImageGridItem(
            viewModel: SelectableListItemModel(
              isSelected: .constant(isSelected),
              item: invalidPodcast,
              isSelecting: isSelecting
            ),
            size: $gridItemSize
          )
        }
      }
    }
  }
  .preview()
  .task {
    do {
      podcast = try await PreviewHelpers.loadPodcast()
      invalidPodcast = try await Create.podcast(
        title: "Broken Image Podcast",
        image: URL(string: "http://nope.com/0.jpg")!
      )
    } catch { Assert.fatal("Couldn't preview podcast thumbnail: \(ErrorKit.message(for: error))") }
  }
}
#endif
