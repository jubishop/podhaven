// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SquareImage: View {
  @Binding var size: CGFloat

  let image: URL
  let cornerRadius: CGFloat

  init(image: URL, size: Binding<CGFloat>, cornerRadius: CGFloat = 8) {
    self.image = image
    _size = size
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
              .font(.system(size: size / 2))
              .frame(width: size / 2, height: size / 2)
            Text("No Image")
              .font(.caption)
              .foregroundColor(.white.opacity(0.8))
          }
        }
      }
    }
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.width
    } action: { newSize in
      size = newSize
    }
    .frame(height: size)
  }
}
