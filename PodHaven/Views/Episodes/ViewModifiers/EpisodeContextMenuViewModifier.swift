// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeContextMenuViewModifier<ViewModel: ManagingEpisodes>: ViewModifier {
  let viewModel: ViewModel
  let episode: ViewModel.EpisodeType

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
          AppIcon.playNow.labelButton {
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

        if episode.saveInCache {
          AppIcon.unsaveEpisodeFromCache.labelButton {
            viewModel.unsaveEpisodeFromCache(episode)
          }
        } else {
          AppIcon.saveEpisodeInCache.labelButton {
            viewModel.saveEpisodeInCache(episode)
          }
        }

        if !episode.finished {
          AppIcon.markEpisodeFinished.labelButton {
            viewModel.markEpisodeFinished(episode)
          }
        }
      }
  }
}

extension View {
  func episodeContextMenu<ViewModel: ManagingEpisodes>(
    viewModel: ViewModel,
    episode: ViewModel.EpisodeType
  ) -> some View {
    self.modifier(EpisodeContextMenuViewModifier(viewModel: viewModel, episode: episode))
  }
}
