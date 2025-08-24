// Copyright Justin Bishop, 2025

import Foundation
import NukeUI
import SwiftUI

struct ImageGridItem: View {
  let cornerRadius: CGFloat
  let image: URL
  @Binding var size: CGFloat

  init(image: URL, size: Binding<CGFloat>, cornerRadius: CGFloat = 8) {
    self.image = image
    _size = size
    self.cornerRadius = cornerRadius
  }

  var body: some View {
    LazyImage(url: image) { state in
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
              .frame(width: size / 2, height: size / 2)
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
    } action: { newSize in
      size = newSize
    }
    .frame(height: size)
  }
}
