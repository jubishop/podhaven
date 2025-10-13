// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PodcastContextMenuModifier: ViewModifier {
  let viewModel: any ManagingPodcasts
  let podcast: any PodcastDisplayable

  func body(content: Content) -> some View {
    content
      .contextMenu {
        if podcast.podcastID != nil {
          AppIcon.queueAtTop.labelButton {
            viewModel.queueLatestEpisodeToTop(podcast)
          }

          AppIcon.queueAtBottom.labelButton {
            viewModel.queueLatestEpisodeToBottom(podcast)
          }

          AppIcon.delete.labelButton {
            viewModel.deletePodcast(podcast)
          }
        }

        if podcast.subscribed {
          AppIcon.unsubscribe.labelButton {
            viewModel.unsubscribePodcast(podcast)
          }
        } else {
          AppIcon.subscribe.labelButton {
            viewModel.subscribePodcast(podcast)
          }
        }
      }
  }
}

extension View {
  func podcastContextMenu(
    viewModel: any ManagingPodcasts,
    podcast: any PodcastDisplayable
  ) -> some View {
    self.modifier(
      PodcastContextMenuModifier(
        viewModel: viewModel,
        podcast: podcast
      )
    )
  }
}
