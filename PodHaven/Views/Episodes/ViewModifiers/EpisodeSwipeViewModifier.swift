// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeSwipeViewModifier<ViewModel: ManagingEpisodes>: ViewModifier {
  let viewModel: ViewModel
  let episode: ViewModel.EpisodeType

  func body(content: Content) -> some View {
    let isEpisodePlaying = viewModel.isEpisodePlaying(episode)
    let isAtBottomOfQueue = viewModel.isEpisodeAtBottomOfQueue(episode)
    let canClearCache = viewModel.canClearCache(episode)

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
          AppIcon.playEpisode.imageButton {
            viewModel.playEpisode(episode)
          }
        }

        switch episode.cacheStatus {
        case .caching:
          if canClearCache {
            AppIcon.cancelEpisodeDownload.imageButton {
              viewModel.uncacheEpisode(episode)
            }
          }
        case .cached:
          if canClearCache {
            AppIcon.uncacheEpisode.imageButton {
              viewModel.uncacheEpisode(episode)
            }
          }
        case .uncached:
          AppIcon.cacheEpisode.imageButton {
            viewModel.cacheEpisode(episode)
          }
        }

        if !episode.finished {
          AppIcon.markEpisodeFinished.imageButton {
            viewModel.markEpisodeFinished(episode)
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
