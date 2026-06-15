// Copyright Justin Bishop, 2026

import SwiftUI

// Title header pinned above a list via .safeAreaInset(edge: .top); gives the icon and
// title the room the inline nav bar can't. The title carries the heading trait for
// VoiceOver while the icon is decorative. The trailing accessory hosts an optional
// per-screen control such as a smart-list edit button.
struct LucideListHeader<Accessory: View>: View {
  private let icon: LucideIcon
  private let title: String
  private let accessory: Accessory

  @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 28

  init(icon: LucideIcon, title: String, @ViewBuilder accessory: () -> Accessory) {
    self.icon = icon
    self.title = title
    self.accessory = accessory()
  }

  var body: some View {
    HStack(spacing: 10) {
      LucideIconView(icon: icon)
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
      Text(title)
        .font(.title2.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      accessory
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
    .padding(.vertical, 10)
    .background(.bar)
  }
}

extension LucideListHeader where Accessory == EmptyView {
  init(icon: LucideIcon, title: String) {
    self.init(icon: icon, title: title) { EmptyView() }
  }
}
