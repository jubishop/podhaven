// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PodcastGridView<Podcast: PodcastDisplayable>: View {
  let podcast: Podcast
  private let isSelecting: Bool
  private let isSelected: Binding<Bool>

  init(
    podcast: Podcast,
    isSelecting: Bool = false,
    isSelected: Binding<Bool> = .constant(false)
  ) {
    self.podcast = podcast
    self.isSelecting = isSelecting
    self.isSelected = isSelected
  }

  var body: some View {
    VStack {
      SquareImage(image: podcast.image)
        .selectable(
          isSelecting: isSelecting,
          isSelected: isSelected
        )
        .subscriptionBadge(subscribed: podcast.subscribed, badgeSize: 16)
      Text(podcast.title)
        .font(.caption)
        .lineLimit(1)
    }
  }
}
