// Copyright Justin Bishop, 2026

import SwiftUI

struct UnreadBadge: View {
  let count: Int
  @ScaledMetric(relativeTo: .footnote) private var diameter: CGFloat = 20

  var body: some View {
    if count > 0 {
      Text(count >= 100 ? "99+" : "\(count)")
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(minWidth: diameter, minHeight: diameter)
        .background(.red, in: Capsule())
    }
  }
}

#if DEBUG
#Preview {
  HStack(spacing: 16) {
    UnreadBadge(count: 1)
    UnreadBadge(count: 12)
    UnreadBadge(count: 137)
    UnreadBadge(count: 0)
  }
  .padding()
}
#endif
