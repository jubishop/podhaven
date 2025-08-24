// Copyright Justin Bishop, 2025

import Foundation
import NukeUI
import SwiftUI

struct ImageGridItem: View {
  let cornerRadius: CGFloat
  let image: URL
  @Binding var width: CGFloat

  init(image: URL, width: Binding<CGFloat>, cornerRadius: CGFloat = 8) {
    self.image = image
    _width = width
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
}
