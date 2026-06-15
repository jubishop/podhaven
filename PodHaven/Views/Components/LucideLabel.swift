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
        .foregroundStyle(.primary)
    }
  }
}
