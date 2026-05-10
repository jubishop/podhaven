// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PodcastContextMenuModifier<ViewModel: ManagingPodcasts>: ViewModifier {
  let viewModel: ViewModel
  let podcast: ViewModel.PodcastType
  let tagIDs: Set<Tag.ID>?

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

        if let tagIDs, podcast.isSaved {
          TagMenu(
            tagIDs: tagIDs,
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
    podcast: ViewModel.PodcastType,
    tagIDs: Set<Tag.ID>? = nil
  ) -> some View {
    self.modifier(
      PodcastContextMenuModifier(
        viewModel: viewModel,
        podcast: podcast,
        tagIDs: tagIDs
      )
    )
  }
}
