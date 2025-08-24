// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeSwipeViewModifier<ViewModel: EpisodeQueueable>: ViewModifier {
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
        .tint(.blue)

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
  func episodeSwipeActions<ViewModel: EpisodeQueueable>(
    viewModel: ViewModel,
    episode: ViewModel.EpisodeType
  ) -> some View {
    self.modifier(EpisodeSwipeViewModifier(viewModel: viewModel, episode: episode))
  }
}
