// Copyright Justin Bishop, 2026

import SwiftUI

struct CountLabel: View {
  let title: String
  let count: Int
  var icon: LucideIcon?

  var body: some View {
    LabeledContent {
      Text("\(count)")
        .foregroundStyle(.secondary)
    } label: {
      if let icon {
        Label {
          Text(title)
        } icon: {
          LucideIconView(icon: icon)
            .frame(width: 24, height: 24)
            .foregroundStyle(.tint)
        }
      } else {
        Text(title)
      }
    }
  }
}
