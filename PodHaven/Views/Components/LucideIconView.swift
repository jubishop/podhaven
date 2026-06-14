// Copyright Justin Bishop, 2026

import SwiftUI

extension LucideIcon {
  // Namespaced asset under Assets.xcassets/LucideIcons, imported as a template
  // so callers tint it via foregroundStyle.
  var image: Image { Image("LucideIcons/\(rawValue)") }
}

struct LucideIconView: View {
  let icon: LucideIcon

  var body: some View {
    icon.image
      .resizable()
      .scaledToFit()
  }
}
