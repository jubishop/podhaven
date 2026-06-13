// Copyright Justin Bishop, 2025

import FactoryKit
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

        Menu {
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
        } label: {
          AppIcon.episodeQueued.label("Queue")
        }

        Menu {
          ratingMenuButtons(showClear: episode.rating != nil) { rating in
            viewModel.rateEpisode(episode, rating: rating)
          }
        } label: {
          AppIcon.rating(for: episode.rating).label("Rate")
        }

        Menu {
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
        } label: {
          AppIcon.cacheEpisode.label("Cache")
        }

        if !episode.finished {
          AppIcon.markEpisodeFinished.labelButton {
            viewModel.markEpisodeFinished(episode)
          }
        }

        AppIcon.transcribeEpisode.labelButton {
          viewModel.transcribeEpisode(episode)
        }

        if let tagIDs = viewModel.tagIDs(for: episode) {
          TagMenu(
            tagIDs: tagIDs,
            onAdd: { viewModel.addTag($0, to: episode) },
            onRemove: { viewModel.removeTag($0, from: episode) }
          )
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
