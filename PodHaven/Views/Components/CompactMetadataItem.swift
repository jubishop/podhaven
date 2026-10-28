// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct CompactMetadataItem: View {
  let appIcon: AppIcon
  let value: String

  var body: some View {
    HStack(spacing: 4) {
      appIcon.image
        .foregroundStyle(.secondary)
      Text(value)
        .foregroundStyle(.secondary)
    }
  }
}
