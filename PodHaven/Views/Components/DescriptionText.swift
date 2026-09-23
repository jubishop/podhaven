// Copyright Justin Bishop, 2026

import SwiftUI

struct DescriptionText: View {
  let blocks: [DescriptionBlock]

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(blocks.indices, id: \.self) { index in
        Text(blocks[index].text)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .multilineTextAlignment(.leading)
  }
}
