// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SelectablePodcastsGridContextMenuModifier: ViewModifier {
  let viewModel: SelectablePodcastsGridViewModel
  let podcast: Podcast

  func body(content: Content) -> some View {
    content
      .contextMenu {
        AppIcon.queueAtTop.labelButton {
          viewModel.queueLatestEpisodeToTop(podcast.id)
        }

        AppIcon.queueAtBottom.labelButton {
          viewModel.queueLatestEpisodeToBottom(podcast.id)
        }

        AppIcon.delete.labelButton {
          viewModel.deletePodcast(podcast.id)
        }

        if podcast.subscribed {
          AppIcon.unsubscribe.labelButton {
            viewModel.unsubscribePodcast(podcast.id)
          }
        } else {
          AppIcon.subscribe.labelButton {
            viewModel.subscribePodcast(podcast.id)
          }
        }
      }
  }
}

extension View {
  func selectablePodcastsGridContextMenu(
    viewModel: SelectablePodcastsGridViewModel,
    podcast: Podcast
  ) -> some View {
    self.modifier(
      SelectablePodcastsGridContextMenuModifier(viewModel: viewModel, podcast: podcast)
    )
  }
}
