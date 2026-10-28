// Copyright Justin Bishop, 2026

import SwiftUI

// Title header pinned above a list via .safeAreaInset(edge: .top); gives the icon and
// title the room the inline nav bar can't. The glass effect lets list rows scroll
// translucently underneath, matching the now-playing header in Up Next.
struct LucideListHeader: View {
  let icon: LucideIcon
  let title: String

  @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 22

  var body: some View {
    HStack(spacing: 8) {
      LucideIconView(icon: icon)
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(.primary)
      Text(title)
        .font(.title3.weight(.semibold))
      Spacer(minLength: 0)
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .glassEffect(in: RoundedRectangle(cornerRadius: 12))
    .padding(.horizontal)
  }
}
