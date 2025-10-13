// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PodcastContextMenuModifier<ViewModel: ManagingPodcasts>: ViewModifier {
  let viewModel: ViewModel
  let podcast: ViewModel.PodcastType

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
  func podcastContextMenu<ViewModel: ManagingPodcasts>(
    viewModel: ViewModel,
    podcast: ViewModel.PodcastType
  ) -> some View {
    self.modifier(
      PodcastContextMenuModifier(
        viewModel: viewModel,
        podcast: podcast
      )
    )
  }
}
