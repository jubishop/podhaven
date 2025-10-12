// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SelectablePodcastsGridContextMenuModifier: ViewModifier {
  let viewModel: SelectablePodcastsGridViewModel
  let podcastWithEpisodeMetadata: PodcastWithEpisodeMetadata

  func body(content: Content) -> some View {
    content
      .contextMenu {
        if viewModel.isSaved(podcastWithEpisodeMetadata) {
          AppIcon.queueAtTop.labelButton {
            viewModel.queueLatestEpisodeToTop(podcastWithEpisodeMetadata)
          }

          AppIcon.queueAtBottom.labelButton {
            viewModel.queueLatestEpisodeToBottom(podcastWithEpisodeMetadata)
          }

          AppIcon.delete.labelButton {
            viewModel.deletePodcast(podcastWithEpisodeMetadata)
          }
        }

        if podcastWithEpisodeMetadata.subscribed {
          AppIcon.unsubscribe.labelButton {
            viewModel.unsubscribePodcast(podcastWithEpisodeMetadata)
          }
        } else {
          AppIcon.subscribe.labelButton {
            viewModel.subscribePodcast(podcastWithEpisodeMetadata)
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
