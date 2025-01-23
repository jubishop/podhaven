// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SizeReader: View {
  var onSizeChange: (CGSize) -> Void

  var body: some View {
    GeometryReader { geometry in
      Color.clear
        .onAppear {
          onSizeChange(geometry.size)
        }
        .onChange(of: geometry.size) { oldSize, newSize in
          onSizeChange(newSize)
        }
    }
  }
}
