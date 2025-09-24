// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SelectablePodcastsGridContextMenuModifier: ViewModifier {
  let viewModel: SelectablePodcastsGridViewModel
  let podcast: Podcast

  func body(content: Content) -> some View {
    content
      .contextMenu {
        AppLabel.queueLatestToTop.labelButton {
          viewModel.queueLatestEpisodeToTop(podcast.id)
        }

        AppLabel.queueLatestToBottom.labelButton {
          viewModel.queueLatestEpisodeToBottom(podcast.id)
        }

        AppLabel.delete.labelButton {
          viewModel.deletePodcast(podcast.id)
        }

        if podcast.subscribed {
          AppLabel.unsubscribe.labelButton {
            viewModel.unsubscribePodcast(podcast.id)
          }
        } else {
          AppLabel.subscribe.labelButton {
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
