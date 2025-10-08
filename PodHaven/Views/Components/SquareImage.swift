// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SquareImage: View {
  @State private var internalSize: CGFloat = 100

  let externalSize: Binding<CGFloat>?
  let image: URL
  let cornerRadius: CGFloat

  var size: Binding<CGFloat> {
    externalSize ?? $internalSize
  }

  init(image: URL, size: Binding<CGFloat>? = nil, cornerRadius: CGFloat = 8) {
    self.image = image
    self.externalSize = size
    self.cornerRadius = cornerRadius
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
      size.wrappedValue = min(newSize.width, newSize.height)
    }
    .frame(width: size.wrappedValue, height: size.wrappedValue)
  }
}
