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
          AppIcon.pauseButton.labelButton {
            viewModel.pauseEpisode(episode)
          }
        } else {
          AppIcon.playEpisode.labelButton {
            viewModel.playEpisode(episode)
          }
        }

        if episode.queued {
          AppIcon.removeFromQueue.labelButton {
            viewModel.removeEpisodeFromQueue(episode)
          }

          if !(episode.queueOrder == 0) {
            AppIcon.moveToTop.labelButton {
              viewModel.queueEpisodeOnTop(episode)
            }
          }

          if !isAtBottomOfQueue {
            AppIcon.moveToBottom.labelButton {
              viewModel.queueEpisodeAtBottom(episode)
            }
          }
        } else {
          AppIcon.queueAtTop.labelButton {
            viewModel.queueEpisodeOnTop(episode)
          }

          AppIcon.queueAtBottom.labelButton {
            viewModel.queueEpisodeAtBottom(episode)
          }
        }

        switch episode.cacheStatus {
        case .caching:
          if canClearCache {
            AppIcon.cancelEpisodeDownload.labelButton {
              viewModel.uncacheEpisode(episode)
            }
          }
        case .cached:
          if canClearCache {
            AppIcon.uncacheEpisode.labelButton {
              viewModel.uncacheEpisode(episode)
            }
          }
        case .uncached:
          AppIcon.cacheEpisode.labelButton {
            viewModel.cacheEpisode(episode)
          }
        }

        if !episode.finished {
          AppIcon.markEpisodeFinished.labelButton {
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
