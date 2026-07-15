// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PodcastSwipeViewModifier<ViewModel: ManagingPodcasts>: ViewModifier {
  let viewModel: ViewModel
  let podcast: ViewModel.PodcastType

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading) {
        AppIcon.queueAtTop
          .imageButton {
            viewModel.queueLatestEpisodeToTop(podcast)
          }
          .accessibilityLabel("Queue Latest Episode at Top")

        AppIcon.queueAtBottom
          .imageButton {
            viewModel.queueLatestEpisodeToBottom(podcast)
          }
          .accessibilityLabel("Queue Latest Episode at Bottom")
      }
      .swipeActions(edge: .trailing) {
        if podcast.isSaved {
          AppIcon.delete
            .imageButton {
              viewModel.deletePodcast(podcast)
            }
            .accessibilityLabel("Delete Podcast")
        }

        if podcast.subscribed {
          AppIcon.unsubscribe.imageButton {
            viewModel.unsubscribePodcast(podcast)
          }
        } else {
          AppIcon.subscribe.imageButton {
            viewModel.subscribePodcast(podcast)
          }
        }
      }
  }
}

extension View {
  func podcastSwipeActions<ViewModel: ManagingPodcasts>(
    viewModel: ViewModel,
    podcast: ViewModel.PodcastType
  ) -> some View {
    self.modifier(
      PodcastSwipeViewModifier(
        viewModel: viewModel,
        podcast: podcast
      )
    )
  }
}
