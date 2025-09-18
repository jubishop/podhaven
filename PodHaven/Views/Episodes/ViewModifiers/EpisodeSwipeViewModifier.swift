// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeSwipeViewModifier<ViewModel: ManagingEpisodes>: ViewModifier {
  let viewModel: ViewModel
  let episode: any EpisodeDisplayable

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading) {
        if episode.queued {
          Button(
            action: { viewModel.queueEpisodeOnTop(episode) },
            label: { AppLabel.moveToTop.image }
          )
          .tint(.blue)

          Button(
            action: { viewModel.removeEpisodeFromQueue(episode) },
            label: { AppLabel.removeFromQueue.image }
          )
          .tint(.red)
        } else {
          Button(
            action: { viewModel.queueEpisodeOnTop(episode) },
            label: { AppLabel.queueAtTop.image }
          )
          .tint(.blue)

          Button(
            action: { viewModel.queueEpisodeAtBottom(episode) },
            label: { AppLabel.queueAtBottom.image }
          )
          .tint(.purple)
        }
      }

      .swipeActions(edge: .trailing) {
        if viewModel.isEpisodePlaying(episode) {
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

        if episode.caching {
          Button(
            action: { viewModel.uncacheEpisode(episode) },
            label: { AppLabel.cancelEpisodeDownload.image }
          )
          .tint(.orange)
        } else if episode.cached {
          Button(
            action: { viewModel.uncacheEpisode(episode) },
            label: { AppLabel.uncacheEpisode.image }
          )
          .tint(.red)
        } else {
          Button(
            action: { viewModel.cacheEpisode(episode) },
            label: { AppLabel.cacheEpisode.image }
          )
          .tint(.blue)
        }
      }
  }
}

extension View {
  func episodeSwipeActions<ViewModel: ManagingEpisodes>(
    viewModel: ViewModel,
    episode: any EpisodeDisplayable
  ) -> some View {
    self.modifier(EpisodeSwipeViewModifier(viewModel: viewModel, episode: episode))
  }
}
