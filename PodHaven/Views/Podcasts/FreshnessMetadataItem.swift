// Copyright Justin Bishop, 2026

import SwiftUI

// Podcast-only counterpart to `CompactMetadataItem`/`DetailedMetadataItem` that
// renders a podcast's freshness cadence (a Lucide asset, sized to the text)
// instead of a system date icon. Kept out of the shared metadata components
// because those compile into the widget target, which has no `FreshnessCadence`.
struct FreshnessMetadataItem: View {
  enum Style {
    case compact
    case detailed
  }

  let cadence: FreshnessCadence
  let value: String
  let style: Style

  @ScaledMetric(relativeTo: .footnote) private var compactIconSize: CGFloat = 14
  @ScaledMetric(relativeTo: .body) private var detailedIconSize: CGFloat = 16

  var body: some View {
    switch style {
    case .compact:
      HStack(spacing: 4) {
        icon(size: compactIconSize)
        Text(value)
      }
      .foregroundStyle(.secondary)
    case .detailed:
      VStack(alignment: .leading, spacing: 4) {
        Label {
          Text(cadence.displayName)
        } icon: {
          icon(size: detailedIconSize)
        }
        Text(value)
      }
      .foregroundStyle(.secondary)
    }
  }

  private func icon(size: CGFloat) -> some View {
    LucideIconView(icon: cadence.icon)
      .frame(width: size, height: size)
  }
}
