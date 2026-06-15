// Copyright Justin Bishop, 2026

import SwiftUI

// Icon + title for a list row. Built on Label so the icon is decorative to
// VoiceOver while the title carries the label; the icon scales with body text.
struct LucideLabel: View {
  let icon: LucideIcon
  let title: String

  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

  var body: some View {
    Label {
      Text(title)
    } icon: {
      LucideIconView(icon: icon)
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(.tint)
    }
  }
}

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
