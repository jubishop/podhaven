// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct UpNextContextMenuViewModifier: ViewModifier {
  let viewModel: UpNextViewModel
  let podcastEpisode: PodcastEpisode

  func body(content: Content) -> some View {
    content
      .contextMenu {
        Button(
          action: { viewModel.playItem(podcastEpisode) },
          label: {
            AppLabel.playEpisode.label
          }
        )

        Button(
          action: { viewModel.showPodcast(podcastEpisode) },
          label: {
            AppLabel.showPodcast.label
          }
        )

        if let queueOrder = podcastEpisode.episode.queueOrder, queueOrder > 0 {
          Button(
            action: { viewModel.moveItemToTop(podcastEpisode) },
            label: {
              AppLabel.moveToTop.label
            }
          )
        }

        Button(
          role: .destructive,
          action: { viewModel.removeItemFromQueue(podcastEpisode) },
          label: {
            AppLabel.removeFromQueue.label
          }
        )

        if !podcastEpisode.episode.cached {
          Button(
            action: { viewModel.cacheItem(podcastEpisode) },
            label: {
              AppLabel.cacheEpisode.label
            }
          )
        }
      }
  }
}

extension View {
  func upNextContextMenu(
    viewModel: UpNextViewModel,
    podcastEpisode: PodcastEpisode
  ) -> some View {
    self.modifier(
      UpNextContextMenuViewModifier(viewModel: viewModel, podcastEpisode: podcastEpisode)
    )
  }
}
