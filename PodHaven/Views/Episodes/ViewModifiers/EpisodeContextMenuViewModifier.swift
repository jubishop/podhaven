// Copyright Justin Bishop, 2025

import FactoryKit
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

        if episode.isSaved, let episodeID = episode.episodeID {
          Divider()
          ratingMenuItems(episodeID: episodeID, currentRating: episode.rating)
        }

        additionalContent()
      }
  }
}

// MARK: - Rating Menu Items

@MainActor
private func ratingMenuItems(
  episodeID: Episode.ID,
  currentRating: EpisodeRating?
) -> some View {
  Group {
    let repo = Container.shared.repo()

    let likeIcon: AppIcon = currentRating == .liked ? .liked : .like
    likeIcon.labelButton {
      Task {
        try? await repo.updateRating(episodeID, rating: currentRating == .liked ? nil : .liked)
      }
    }

    let loveIcon: AppIcon = currentRating == .loved ? .loved : .love
    loveIcon.labelButton {
      Task {
        try? await repo.updateRating(episodeID, rating: currentRating == .loved ? nil : .loved)
      }
    }

    let dislikeIcon: AppIcon = currentRating == .disliked ? .disliked : .dislike
    dislikeIcon.labelButton {
      Task {
        try? await repo.updateRating(
          episodeID,
          rating: currentRating == .disliked ? nil : .disliked
        )
      }
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
