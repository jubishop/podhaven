// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct SelectableSquareImage<Item: Gridable>: View {
  @Binding var size: CGFloat

  private let viewModel: SelectableListItemModel<Item>
  let cornerRadius: CGFloat

  init(
    viewModel: SelectableListItemModel<Item>,
    size: Binding<CGFloat>,
    cornerRadius: CGFloat = 8
  ) {
    self.viewModel = viewModel
    self._size = size
    self.cornerRadius = cornerRadius
  }

  var body: some View {
    VStack {
      ZStack {
        SquareImage(image: viewModel.item.image, size: $size, cornerRadius: cornerRadius)

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
                    : AppLabel.selectionEmpty)
                    .image
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
    }
  }
}
