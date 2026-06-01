// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

struct QueueWidgetView: View {
  let entry: QueueEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      OptionalLink(url: URL(string: "podhaven://widget/queue")) {
        HStack {
          AppIcon.episodes.label("Up Next")
            .fontWeight(.semibold)
          Spacer()
        }
        .font(.callout)
      }
      .padding(.bottom, 6)

      QueueListView(items: entry.items)
    }
    .dynamicTypeSize(.small ... .xxxLarge)
  }
}

#if DEBUG
#Preview("Queue - Large", as: .systemLarge) {
  QueueWidget()
} timeline: {
  QueueEntry.preview
  QueueEntry.empty
}
#endif
