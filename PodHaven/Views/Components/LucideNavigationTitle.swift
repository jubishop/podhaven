// Copyright Justin Bishop, 2026

import SwiftUI

// Icon + title for a navigation bar's principal toolbar item. The title conveys
// the destination, so the icon is hidden from VoiceOver; it scales with the
// headline title. A custom principal view doesn't inherit the system title's
// header trait, so the title restores it for the VoiceOver headings rotor.
struct LucideNavigationTitle: View {
  let icon: LucideIcon
  let title: String

  @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 20

  var body: some View {
    HStack(spacing: 6) {
      LucideIconView(icon: icon)
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      Text(title)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
    }
  }
}
