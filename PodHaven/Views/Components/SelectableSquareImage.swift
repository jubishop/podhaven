// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct SelectableSquareImage: View {
  @State private var internalSize: CGFloat = 100
  @Binding private var isSelected: Bool

  private let externalSize: Binding<CGFloat>?
  private let image: URL
  private let isSelecting: Bool
  private let cornerRadius: CGFloat
  private let sizeConstraint: SquareImage.SizeConstraint

  var size: Binding<CGFloat> {
    externalSize ?? $internalSize
  }

  init(
    image: URL,
    size: Binding<CGFloat>? = nil,
    cornerRadius: CGFloat = 8,
    sizeConstraint: SquareImage.SizeConstraint = .both,
    isSelected: Binding<Bool>,
    isSelecting: Bool
  ) {
    self.image = image
    self.externalSize = size
    self.cornerRadius = cornerRadius
    self.sizeConstraint = sizeConstraint
    self._isSelected = isSelected
    self.isSelecting = isSelecting
  }

  var body: some View {
    VStack {
      ZStack {
        SquareImage(
          image: image,
          size: size,
          cornerRadius: cornerRadius,
          sizeConstraint: sizeConstraint
        )

        if isSelecting {
          Group {
            Rectangle()
              .fill(Color.black.opacity(isSelected ? 0.0 : 0.5))
              .cornerRadius(cornerRadius)

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
          }
          .frame(
            width: sizeConstraint == .width ? nil : size.wrappedValue,
            height: sizeConstraint == .height ? nil : size.wrappedValue
          )
        }
      }
    }
  }
}
