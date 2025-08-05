// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeQueueableSwipeViewModifier<ViewModel: EpisodeQueueable>: ViewModifier {
  let viewModel: ViewModel
  let episode: ViewModel.EpisodeType

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading) {
        Button(
          action: { viewModel.queueEpisodeOnTop(episode) },
          label: {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
          }
        )
        .tint(.orange)

        Button(
          action: { viewModel.queueEpisodeAtBottom(episode) },
          label: {
            Image(systemName: "text.line.last.and.arrowtriangle.forward")
          }
        )
        .tint(.purple)
      }
      .swipeActions(edge: .trailing) {
        Button(
          action: { viewModel.playEpisode(episode) },
          label: {
            Image(systemName: "play.fill")
          }
        )
        .tint(.green)
      }
  }
}

extension View {
  func episodeQueueableSwipeActions<ViewModel: EpisodeQueueable>(
    viewModel: ViewModel,
    episode: ViewModel.EpisodeType
  ) -> some View {
    self.modifier(EpisodeQueueableSwipeViewModifier(viewModel: viewModel, episode: episode))
  }
}
