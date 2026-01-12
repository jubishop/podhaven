// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct DetailedMetadataItem: View {
  let appIcon: AppIcon
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      appIcon.label
        .foregroundStyle(.secondary)
      Text(value)
        .foregroundStyle(.secondary)
    }
  }
}
