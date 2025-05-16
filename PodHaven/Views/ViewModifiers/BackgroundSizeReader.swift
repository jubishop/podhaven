// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct BackgroundSizeReaderViewModifier: ViewModifier {
  let onSizeChange: (CGSize) -> Void

  init(onSizeChange: @escaping (CGSize) -> Void) {
    self.onSizeChange = onSizeChange
  }

  func body(content: Content) -> some View {
    content
      .background(SizeReader(onSizeChange: onSizeChange))
  }
}

extension View {
  func backgroundSizeReader(onSizeChange: @escaping (CGSize) -> Void) -> some View {
    self.modifier(BackgroundSizeReaderViewModifier(onSizeChange: onSizeChange))
  }
}
