// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SquareImage: View {
  enum SizeConstraint {
    case both
    case width
    case height
  }

  @State private var internalSize: CGFloat = 100

  private let externalSize: Binding<CGFloat>?
  private let image: URL
  private let cornerRadius: CGFloat
  private let sizeConstraint: SizeConstraint

  var size: Binding<CGFloat> {
    externalSize ?? $internalSize
  }

  init(
    image: URL,
    size: Binding<CGFloat>? = nil,
    cornerRadius: CGFloat = 8,
    sizeConstraint: SizeConstraint = .both
  ) {
    self.image = image
    self.externalSize = size
    self.cornerRadius = cornerRadius
    self.sizeConstraint = sizeConstraint
  }

  var body: some View {
    PodLazyImage(url: image) { state in
      if let image = state.image {
        image
          .resizable()
          .cornerRadius(cornerRadius)
      } else {
        ZStack {
          Color.gray
            .cornerRadius(cornerRadius)
          VStack {
            AppIcon.noImage.coloredImage
              .font(.system(size: size.wrappedValue / 2))
              .frame(width: size.wrappedValue / 2, height: size.wrappedValue / 2)
            Text("No Image")
              .font(.caption)
              .foregroundColor(.white.opacity(0.8))
          }
        }
      }
    }
    .onGeometryChange(for: CGSize.self) { geometry in
      geometry.size
    } action: { newSize in
      size.wrappedValue =
        switch sizeConstraint {
        case .both: min(newSize.width, newSize.height)
        case .width: newSize.width
        case .height: newSize.height
        }
    }
    .frame(
      width: sizeConstraint == .width ? nil : size.wrappedValue,
      height: sizeConstraint == .height ? nil : size.wrappedValue
    )
  }
}
