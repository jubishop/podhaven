// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PodcastContextMenuModifier<ViewModel: ManagingPodcasts>: ViewModifier {
  let viewModel: ViewModel
  let podcastWithMetadata: PodcastWithEpisodeMetadata<ViewModel.PodcastType>

  private var podcast: ViewModel.PodcastType { podcastWithMetadata.podcast }

  func body(content: Content) -> some View {
    content
      .contextMenu {
        AppIcon.queueAtTop.labelButton {
          viewModel.queueLatestEpisodeToTop(podcast)
        }

        AppIcon.queueAtBottom.labelButton {
          viewModel.queueLatestEpisodeToBottom(podcast)
        }

        if podcast.isSaved {
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

        if podcast.isSaved {
          TagMenu(
            tagIDs: podcastWithMetadata.tagIDs,
            onAdd: { viewModel.addTag($0, to: podcast) },
            onRemove: { viewModel.removeTag($0, from: podcast) }
          )
        }
      }
  }
}

extension View {
  func podcastContextMenu<ViewModel: ManagingPodcasts>(
    viewModel: ViewModel,
    podcastWithMetadata: PodcastWithEpisodeMetadata<ViewModel.PodcastType>
  ) -> some View {
    self.modifier(
      PodcastContextMenuModifier(
        viewModel: viewModel,
        podcastWithMetadata: podcastWithMetadata
      )
    )
  }
}
