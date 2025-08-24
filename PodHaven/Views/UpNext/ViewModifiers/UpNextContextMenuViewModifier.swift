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
            Label("Play Episode", systemImage: "play.fill")
          }
        )

        if let queueOrder = podcastEpisode.episode.queueOrder, queueOrder > 0 {
          Button(
            action: { viewModel.moveItemToTop(podcastEpisode) },
            label: {
              Label("Move to Top", systemImage: "arrow.up.to.line")
            }
          )
        }

        Button(
          role: .destructive,
          action: { viewModel.removeItemFromQueue(podcastEpisode) },
          label: {
            Label("Remove from Queue", systemImage: "trash")
          }
        )

        if podcastEpisode.episode.cachedFilename == nil {
          Button(
            action: { viewModel.cacheItem(podcastEpisode) },
            label: {
              Label("Cache Episode", systemImage: "arrow.down.circle.fill")
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
