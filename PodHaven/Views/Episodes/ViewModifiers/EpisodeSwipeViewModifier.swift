// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

struct EpisodeSwipeViewModifier<ViewModel: ManagingEpisodes>: ViewModifier {
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings

  let viewModel: ViewModel
  let episode: ViewModel.EpisodeType

  @State private var activeDialog: Dialog?

  private enum Dialog: Identifiable {
    case rate
    case tag

    var id: Self { self }
  }

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading) {
        leadingActions
      }
      .swipeActions(edge: .trailing) {
        ForEach(userSettings.episodeSwipeActions, id: \.self) { action in
          trailingAction(action)
        }
      }
      .confirmationDialog(
        "Rate Episode",
        isPresented: dialogBinding(.rate),
        titleVisibility: .visible
      ) {
        ratingDialogButtons
      }
      .confirmationDialog(
        "Add Tag",
        isPresented: dialogBinding(.tag),
        titleVisibility: .visible
      ) {
        tagDialogButtons
      }
  }

  // MARK: - Leading (Queue) Actions

  @ViewBuilder private var leadingActions: some View {
    if episode.queued {
      AppIcon.removeFromQueue.imageButton {
        viewModel.removeEpisodeFromQueue(episode)
      }

      if !(episode.queueOrder == 0) {
        AppIcon.moveToTop.imageButton {
          viewModel.queueEpisodeOnTop(episode, swipeAction: true)
        }
      }

      if !viewModel.isEpisodeAtBottomOfQueue(episode) {
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

  // MARK: - Trailing (Configurable) Actions

  @ViewBuilder private func trailingAction(_ action: UserSettings.EpisodeSwipeAction) -> some View {
    switch action {
    case .playPause:
      if viewModel.isEpisodePlaying(episode) {
        AppIcon.pauseButton.imageButton {
          viewModel.pauseEpisode(episode)
        }
      } else {
        AppIcon.playNow.imageButton {
          viewModel.playEpisode(episode)
        }
      }

    case .rate:
      AppIcon.rating(for: episode.rating)
        .imageButton {
          activeDialog = .rate
        }

    case .markFinished:
      if !episode.finished {
        AppIcon.markEpisodeFinished.imageButton {
          viewModel.markEpisodeFinished(episode)
        }
      }

    case .cache:
      switch episode.cacheStatus {
      case .uncached:
        AppIcon.cacheEpisode.imageButton {
          viewModel.cacheEpisode(episode)
        }
      case .caching:
        if viewModel.canClearCache(episode) {
          AppIcon.cancelEpisodeDownload.imageButton {
            viewModel.uncacheEpisode(episode)
          }
        }
      case .cached:
        if viewModel.canClearCache(episode) {
          AppIcon.uncacheEpisode.imageButton {
            viewModel.uncacheEpisode(episode)
          }
        }
      }

    case .addTag:
      if !addableTags.isEmpty {
        AppIcon.addTag.imageButton {
          activeDialog = .tag
        }
      }
    }
  }

  // MARK: - Dialogs

  @ViewBuilder private var ratingDialogButtons: some View {
    Button(AppIcon.loveEpisode.text) {
      viewModel.rateEpisode(episode, rating: .loved)
    }
    Button(AppIcon.likeEpisode.text) {
      viewModel.rateEpisode(episode, rating: .liked)
    }
    Button(AppIcon.dislikeEpisode.text) {
      viewModel.rateEpisode(episode, rating: .disliked)
    }
    Button(AppIcon.notInterestedEpisode.text) {
      viewModel.rateEpisode(episode, rating: .notInterested)
    }
    if episode.rating != nil {
      Button(AppIcon.clearRating.text, role: .destructive) {
        viewModel.rateEpisode(episode, rating: nil)
      }
    }
  }

  @ViewBuilder private var tagDialogButtons: some View {
    ForEach(addableTags) { tag in
      Button(tag.name) {
        viewModel.addTag(tag.id, to: episode)
      }
    }
  }

  // MARK: - Helpers

  private var addableTags: [Tag] {
    guard let assigned = viewModel.tagIDs(for: episode) else { return [] }
    return sharedState.tags.filter { !assigned.contains($0.id) }
  }

  private func dialogBinding(_ dialog: Dialog) -> Binding<Bool> {
    Binding(
      get: { activeDialog == dialog },
      set: { isPresented in
        if isPresented {
          activeDialog = dialog
        } else if activeDialog == dialog {
          activeDialog = nil
        }
      }
    )
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
