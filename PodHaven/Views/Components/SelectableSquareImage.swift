// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct SelectableSquareImage: View {
  @Binding var size: CGFloat
  @Binding var isSelected: Bool

  let image: URL
  let isSelecting: Bool
  let cornerRadius: CGFloat

  init(
    image: URL,
    size: Binding<CGFloat>,
    cornerRadius: CGFloat = 8,
    isSelected: Binding<Bool>,
    isSelecting: Bool
  ) {
    self.image = image
    self._size = size
    self.cornerRadius = cornerRadius
    self._isSelected = isSelected
    self.isSelecting = isSelecting
  }

  var body: some View {
    VStack {
      ZStack {
        SquareImage(image: image, size: $size, cornerRadius: cornerRadius)

        if isSelecting {
          Rectangle()
            .fill(Color.black.opacity(isSelected ? 0.0 : 0.5))
            .cornerRadius(cornerRadius)
            .frame(height: size)

          VStack {
            Spacer()
            HStack {
              Spacer()
              Button(
                action: {
                  isSelected.toggle()
                },
                label: {
                  (isSelected
                    ? AppIcon.selectionFilled
                    : AppIcon.selectionEmpty)
                    .image
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .blue : .white)
                    .background(
                      Circle()
                        .fill(Color.black.opacity(0.5))
                        .padding(-3)
                    )
                }
              )
              .buttonStyle(BorderlessButtonStyle())
              .padding(8)
            }
          }
          .frame(height: size)
        }
      }
    }
  }
}
