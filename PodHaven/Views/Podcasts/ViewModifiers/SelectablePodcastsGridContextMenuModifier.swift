// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SelectablePodcastsGridContextMenuModifier: ViewModifier {
  let viewModel: SelectablePodcastsGridViewModel
  let podcastWithEpisodeMetadata: PodcastWithEpisodeMetadata

  func body(content: Content) -> some View {
    content
      .contextMenu {
        AppIcon.queueAtTop.labelButton {
          viewModel.queueLatestEpisodeToTop(podcastWithEpisodeMetadata.id)
        }

        AppIcon.queueAtBottom.labelButton {
          viewModel.queueLatestEpisodeToBottom(podcastWithEpisodeMetadata.id)
        }

        AppIcon.delete.labelButton {
          viewModel.deletePodcast(podcastWithEpisodeMetadata.id)
        }

        if podcastWithEpisodeMetadata.subscribed {
          AppIcon.unsubscribe.labelButton {
            viewModel.unsubscribePodcast(podcastWithEpisodeMetadata.id)
          }
        } else {
          AppIcon.subscribe.labelButton {
            viewModel.subscribePodcast(podcastWithEpisodeMetadata.id)
          }
        }
      }
  }
}

extension View {
  func selectablePodcastsGridContextMenu(
    viewModel: SelectablePodcastsGridViewModel,
    podcastWithEpisodeMetadata: PodcastWithEpisodeMetadata
  ) -> some View {
    self.modifier(
      SelectablePodcastsGridContextMenuModifier(
        viewModel: viewModel,
        podcastWithEpisodeMetadata: podcastWithEpisodeMetadata
      )
    )
  }
}
