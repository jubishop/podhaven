// Copyright Justin Bishop, 2026

import SwiftUI

struct DescriptionText: View {
  let blocks: [DescriptionBlock]
  var openTimestamp: (@MainActor (String) -> Void)?

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(blocks.indices, id: \.self) { index in
        Text(blocks[index].text)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .multilineTextAlignment(.leading)
    .environment(
      \.openURL,
      OpenURLAction { url in
        if let openTimestamp, let timestamp = Timestamp.timestamp(fromURL: url) {
          openTimestamp(timestamp)
          return .handled
        }
        return HTMLContent.allowsLink(url) ? .systemAction : .discarded
      }
    )
  }
}
