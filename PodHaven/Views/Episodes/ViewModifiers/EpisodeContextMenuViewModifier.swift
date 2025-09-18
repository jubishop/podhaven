// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeContextMenuViewModifier<
  ViewModel: ManagingEpisodes,
  AdditionalContent: View
>: ViewModifier {
  let viewModel: ViewModel
  let episode: any EpisodeDisplayable
  @ViewBuilder let additionalContent: () -> AdditionalContent

  func body(content: Content) -> some View {
    let isEpisodePlaying = viewModel.isEpisodePlaying(episode)
    let canClearCache = viewModel.canClearCache(episode)

    content
      .contextMenu {
        if isEpisodePlaying {
          Button(
            action: { viewModel.pauseEpisode(episode) },
            label: { AppLabel.pauseButton.label }
          )
          .tint(.yellow)
        } else {
          Button(
            action: { viewModel.playEpisode(episode) },
            label: { AppLabel.playEpisode.label }
          )
          .tint(.green)
        }

        if episode.queued {
          Button(
            action: { viewModel.queueEpisodeOnTop(episode) },
            label: { AppLabel.moveToTop.label }
          )
          .tint(.blue)

          Button(
            action: { viewModel.removeEpisodeFromQueue(episode) },
            label: { AppLabel.removeFromQueue.label }
          )
          .tint(.red)
        } else {
          Button(
            action: { viewModel.queueEpisodeOnTop(episode) },
            label: { AppLabel.queueAtTop.label }
          )
          .tint(.blue)

          Button(
            action: { viewModel.queueEpisodeAtBottom(episode) },
            label: { AppLabel.queueAtBottom.label }
          )
          .tint(.purple)
        }

        if !episode.finished {
          Button(
            action: { viewModel.markEpisodeFinished(episode) },
            label: { AppLabel.markEpisodeFinished.label }
          )
          .tint(.mint)
        }

        if episode.caching {
          if canClearCache {
            Button(
              action: { viewModel.uncacheEpisode(episode) },
              label: { AppLabel.cancelEpisodeDownload.label }
            )
            .tint(.orange)
          }
        } else if episode.cached {
          if canClearCache {
            Button(
              action: { viewModel.uncacheEpisode(episode) },
              label: { AppLabel.uncacheEpisode.label }
            )
            .tint(.red)
          }
        } else {
          Button(
            action: { viewModel.cacheEpisode(episode) },
            label: { AppLabel.cacheEpisode.label }
          )
          .tint(.blue)
        }

        additionalContent()
      }
  }
}

extension View {
  func episodeContextMenu<ViewModel: ManagingEpisodes, AdditionalContent: View>(
    viewModel: ViewModel,
    episode: any EpisodeDisplayable,
    @ViewBuilder additionalContent: @escaping () -> AdditionalContent = { EmptyView() }
  ) -> some View {
    self.modifier(
      EpisodeContextMenuViewModifier(
        viewModel: viewModel,
        episode: episode,
        additionalContent: additionalContent
      )
    )
  }
}
