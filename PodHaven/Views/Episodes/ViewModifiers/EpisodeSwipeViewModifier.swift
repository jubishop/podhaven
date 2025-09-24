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
          Button(
            action: { viewModel.removeEpisodeFromQueue(episode) },
            label: { AppLabel.removeFromQueue.image }
          )
          .tint(.red)

          if !(episode.queueOrder == 0) {
            Button(
              action: { viewModel.queueEpisodeOnTop(episode, swipeAction: true) },
              label: { AppLabel.moveToTop.image }
            )
            .tint(.blue)
          }

          if !isAtBottomOfQueue {
            Button(
              action: { viewModel.queueEpisodeAtBottom(episode, swipeAction: true) },
              label: { AppLabel.moveToBottom.image }
            )
            .tint(.purple)
          }
        } else {
          Button(
            action: { viewModel.queueEpisodeOnTop(episode, swipeAction: true) },
            label: { AppLabel.queueAtTop.image }
          )
          .tint(.blue)

          Button(
            action: { viewModel.queueEpisodeAtBottom(episode, swipeAction: true) },
            label: { AppLabel.queueAtBottom.image }
          )
          .tint(.purple)
        }
      }

      .swipeActions(edge: .trailing) {
        if isEpisodePlaying {
          Button(
            action: { viewModel.pauseEpisode(episode) },
            label: { AppLabel.pauseButton.image }
          )
          .tint(.yellow)
        } else {
          Button(
            action: { viewModel.playEpisode(episode) },
            label: { AppLabel.playEpisode.image }
          )
          .tint(.green)
        }

        switch episode.cacheStatus {
        case .caching:
          if canClearCache {
            Button(
              action: { viewModel.uncacheEpisode(episode) },
              label: { AppLabel.cancelEpisodeDownload.image }
            )
            .tint(.orange)
          }
        case .cached:
          if canClearCache {
            Button(
              action: { viewModel.uncacheEpisode(episode) },
              label: { AppLabel.uncacheEpisode.image }
            )
            .tint(.red)
          }
        case .uncached:
          Button(
            action: { viewModel.cacheEpisode(episode) },
            label: { AppLabel.cacheEpisode.image }
          )
          .tint(.blue)
        }

        if !episode.finished {
          Button(
            action: { viewModel.markEpisodeFinished(episode) },
            label: { AppLabel.markEpisodeFinished.image }
          )
          .tint(.mint)
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
