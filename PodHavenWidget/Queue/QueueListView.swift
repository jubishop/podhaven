// Copyright Justin Bishop, 2026

import SwiftUI

// Height-driven queue list: rows fill the available space top-to-bottom and
// TruncatingVStack crops any that don't fit, always showing at least one.
struct QueueListView: View {
  let items: [QueueEntry.QueueEntryItem]
  var imageSize: CGFloat = 56

  var body: some View {
    if items.isEmpty {
      VStack(spacing: 8) {
        AppIcon.upNext.rawImage
          .font(.largeTitle)
          .foregroundStyle(.quaternary)
        Text("Add episodes to your queue")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      TruncatingVStack {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          VStack(spacing: 0) {
            if index > 0 {
              Divider()
                .padding(.leading, imageSize + 4)
                .padding(.trailing, 14)
            }

            QueueRowView(item: item, imageSize: imageSize)
          }
        }
      }
    }
  }
}
