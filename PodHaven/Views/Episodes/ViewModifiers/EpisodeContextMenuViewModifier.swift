// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeContextMenuViewModifier<
  ViewModel: ManagingEpisodes,
  AdditionalContent: View
>: ViewModifier {
  let viewModel: ViewModel
  let episode: ViewModel.EpisodeType
  @ViewBuilder let additionalContent: () -> AdditionalContent

  func body(content: Content) -> some View {
    let isEpisodePlaying = viewModel.isEpisodePlaying(episode)
    let isAtBottomOfQueue = viewModel.isEpisodeAtBottomOfQueue(episode)
    let canClearCache = viewModel.canClearCache(episode)

    content
      .contextMenu {
        if isEpisodePlaying {
          AppLabel.pauseButton.labelButton {
            viewModel.pauseEpisode(episode)
          }
        } else {
          AppLabel.playEpisode.labelButton {
            viewModel.playEpisode(episode)
          }
        }

        if episode.queued {
          AppLabel.removeFromQueue.labelButton {
            viewModel.removeEpisodeFromQueue(episode)
          }

          if !(episode.queueOrder == 0) {
            AppLabel.moveToTop.labelButton {
              viewModel.queueEpisodeOnTop(episode)
            }
          }

          if !isAtBottomOfQueue {
            AppLabel.moveToBottom.labelButton {
              viewModel.queueEpisodeAtBottom(episode)
            }
          }
        } else {
          AppLabel.queueAtTop.labelButton {
            viewModel.queueEpisodeOnTop(episode)
          }

          AppLabel.queueAtBottom.labelButton {
            viewModel.queueEpisodeAtBottom(episode)
          }
        }

        switch episode.cacheStatus {
        case .caching:
          if canClearCache {
            AppLabel.cancelEpisodeDownload.labelButton {
              viewModel.uncacheEpisode(episode)
            }
          }
        case .cached:
          if canClearCache {
            AppLabel.uncacheEpisode.labelButton {
              viewModel.uncacheEpisode(episode)
            }
          }
        case .uncached:
          AppLabel.cacheEpisode.labelButton {
            viewModel.cacheEpisode(episode)
          }
        }

        if !episode.finished {
          AppLabel.markEpisodeFinished.labelButton {
            viewModel.markEpisodeFinished(episode)
          }
        }

        additionalContent()
      }
  }
}

extension View {
  func episodeContextMenu<ViewModel: ManagingEpisodes, AdditionalContent: View>(
    viewModel: ViewModel,
    episode: ViewModel.EpisodeType,
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
