// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeSwipeModifier<ViewModel: EpisodeQueueable & EpisodePlayable>: ViewModifier {
  let viewModel: ViewModel
  let episode: ViewModel.EpisodeType

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading) {
        Button(
          action: { viewModel.queueEpisodeOnTop(episode) },
          label: {
            Label("Queue on Top", systemImage: "text.line.first.and.arrowtriangle.forward")
          }
        )
        .tint(.orange)

        Button(
          action: { viewModel.queueEpisodeAtBottom(episode) },
          label: {
            Label("Queue on Bottom", systemImage: "text.line.last.and.arrowtriangle.forward")
          }
        )
        .tint(.purple)
      }
      .swipeActions(edge: .trailing) {
        Button(
          action: { viewModel.playEpisode(episode) },
          label: {
            Label("Play Now", systemImage: "play.fill")
          }
        )
        .tint(.green)
      }
  }
}

extension View {
  func episodeSwipeActions<ViewModel: EpisodeQueueable & EpisodePlayable>(
    viewModel: ViewModel,
    episode: ViewModel.EpisodeType
  ) -> some View {
    self.modifier(EpisodeSwipeModifier(viewModel: viewModel, episode: episode))
  }
}


