// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PodcastGridView: View {
  let podcast: any PodcastDisplayable
  private let isSelecting: Bool
  private let isSelected: Binding<Bool>

  init(
    podcast: any PodcastDisplayable,
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
        .overlay(alignment: .bottomLeading) {
          if podcast.subscribed {
            subscribedBadge
          }
        }
      Text(podcast.title)
        .font(.caption)
        .lineLimit(1)
    }
  }

  private var subscribedBadge: some View {
    AppIcon.subscribed.image
      .font(.system(size: 16, weight: .semibold))
      .padding(4)
      .background(.ultraThinMaterial, in: Circle())
      .shadow(radius: 1)
  }
}
