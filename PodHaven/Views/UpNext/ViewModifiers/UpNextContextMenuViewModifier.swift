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
          action: { viewModel.playEpisode(podcastEpisode) },
          label: { AppLabel.playEpisode.label }
        )

        Button(
          action: { viewModel.showPodcast(podcastEpisode) },
          label: { AppLabel.showPodcast.label }
        )

        if let queueOrder = podcastEpisode.episode.queueOrder, queueOrder > 0 {
          Button(
            action: { viewModel.queueEpisodeOnTop(podcastEpisode) },
            label: { AppLabel.moveToTop.label }
          )
        }

        Button(
          role: .destructive,
          action: { viewModel.removeEpisodeFromQueue(podcastEpisode) },
          label: { AppLabel.removeFromQueue.label }
        )

        if !podcastEpisode.episode.cached {
          Button(
            action: { viewModel.cacheEpisode(podcastEpisode) },
            label: { AppLabel.cacheEpisode.label }
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
