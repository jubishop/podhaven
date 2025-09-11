// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct UpNextSwipeViewModifier: ViewModifier {
  let viewModel: UpNextViewModel
  let podcastEpisode: PodcastEpisode

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading) {
        Button(
          action: { viewModel.moveItemToTop(podcastEpisode) },
          label: { AppLabel.moveToTop.image }
        )
        .tint(.blue)

        Button(
          role: .destructive,
          action: { viewModel.removeItemFromQueue(podcastEpisode) },
          label: { AppLabel.removeFromQueue.image }
        )
        .tint(.red)
      }

      .swipeActions(edge: .trailing) {
        Button(
          action: { viewModel.playItem(podcastEpisode) },
          label: { AppLabel.playEpisode.image }
        )
        .tint(.green)
      }
  }
}

extension View {
  func upNextSwipeActions(
    viewModel: UpNextViewModel,
    podcastEpisode: PodcastEpisode
  ) -> some View {
    self.modifier(UpNextSwipeViewModifier(viewModel: viewModel, podcastEpisode: podcastEpisode))
  }
}
