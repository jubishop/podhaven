// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import IdentifiedCollections
import SwiftUI

struct EpisodeContextMenuViewModifier<ViewModel: ManagingEpisodes>: ViewModifier {
  @DynamicInjected(\.sharedState) private var sharedState

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

        if let tagIDs = viewModel.tagIDs(for: episode) {
          tagMenu(tagIDs: tagIDs)
        }
      }
  }

  // Filtered Add/Remove submenus. Hidden whole-cloth when both filtered
  // lists are empty so we never offer a submenu that would no-op.
  @ViewBuilder
  private func tagMenu(tagIDs: Set<Tag.ID>) -> some View {
    let allTags = sharedState.tags
    let addable = allTags.filter { !tagIDs.contains($0.id) }
    let removable = allTags.filter { tagIDs.contains($0.id) }

    if !addable.isEmpty || !removable.isEmpty {
      Menu {
        if !addable.isEmpty {
          Menu {
            ForEach(addable) { tag in
              Button(tag.name) {
                viewModel.addTag(tag.id, to: episode)
              }
            }
          } label: {
            AppIcon.addTag.label("Add Tag")
          }
        }

        if !removable.isEmpty {
          Menu {
            ForEach(removable) { tag in
              Button(tag.name) {
                viewModel.removeTag(tag.id, from: episode)
              }
            }
          } label: {
            AppIcon.removeTag.label("Remove Tag")
          }
        }
      } label: {
        AppIcon.tag.label("Tag")
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
