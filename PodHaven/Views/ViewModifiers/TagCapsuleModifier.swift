// Copyright Justin Bishop, 2026

import SwiftUI

struct TagCapsuleModifier: ViewModifier {
  let color: Color

  func body(content: Content) -> some View {
    content
      .font(.subheadline)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(color.opacity(0.15))
      .clipShape(Capsule())
  }
}

extension View {
  func tagCapsule(color: Color) -> some View {
    modifier(TagCapsuleModifier(color: color))
  }
}
