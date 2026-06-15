// Copyright Justin Bishop, 2026

import SwiftUI

struct CountLabel: View {
  let title: String
  let count: Int

  var body: some View {
    LabeledContent(title) {
      Text("\(count)")
        .foregroundStyle(.secondary)
    }
  }
}
