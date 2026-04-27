// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeSwipeViewModifier<ViewModel: ManagingEpisodes>: ViewModifier {
  let viewModel: ViewModel
  let episode: ViewModel.EpisodeType

  @State private var isRatingDialogPresented = false

  func body(content: Content) -> some View {
    let isEpisodePlaying = viewModel.isEpisodePlaying(episode)
    let isAtBottomOfQueue = viewModel.isEpisodeAtBottomOfQueue(episode)

    content
      .swipeActions(edge: .leading) {
        if episode.queued {
          AppIcon.removeFromQueue.imageButton {
            viewModel.removeEpisodeFromQueue(episode)
          }

          if !(episode.queueOrder == 0) {
            AppIcon.moveToTop.imageButton {
              viewModel.queueEpisodeOnTop(episode, swipeAction: true)
            }
          }

          if !isAtBottomOfQueue {
            AppIcon.moveToBottom.imageButton {
              viewModel.queueEpisodeAtBottom(episode, swipeAction: true)
            }
          }
        } else {
          AppIcon.queueAtTop.imageButton {
            viewModel.queueEpisodeOnTop(episode, swipeAction: true)
          }

          AppIcon.queueAtBottom.imageButton {
            viewModel.queueEpisodeAtBottom(episode, swipeAction: true)
          }
        }
      }

      .swipeActions(edge: .trailing) {
        if isEpisodePlaying {
          AppIcon.pauseButton.imageButton {
            viewModel.pauseEpisode(episode)
          }
        } else {
          AppIcon.playNow.imageButton {
            viewModel.playEpisode(episode)
          }
        }

        AppIcon.rating(for: episode.rating)
          .imageButton {
            isRatingDialogPresented = true
          }
      }
      .confirmationDialog(
        "Rate Episode",
        isPresented: $isRatingDialogPresented,
        titleVisibility: .visible
      ) {
        Button(AppIcon.loveEpisode.text) {
          viewModel.rateEpisode(episode, rating: .loved)
        }
        Button(AppIcon.likeEpisode.text) {
          viewModel.rateEpisode(episode, rating: .liked)
        }
        Button(AppIcon.dislikeEpisode.text) {
          viewModel.rateEpisode(episode, rating: .disliked)
        }
        if episode.rating != nil {
          Button(AppIcon.clearRating.text, role: .destructive) {
            viewModel.rateEpisode(episode, rating: nil)
          }
        }
      }
  }
}

extension View {
  func episodeSwipeActions<ViewModel: ManagingEpisodes>(
    viewModel: ViewModel,
    episode: ViewModel.EpisodeType
  ) -> some View {
    self.modifier(EpisodeSwipeViewModifier(viewModel: viewModel, episode: episode))
  }
}
