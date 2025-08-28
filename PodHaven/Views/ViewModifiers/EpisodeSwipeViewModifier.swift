// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeSwipeViewModifier<ViewModel: ManagingEpisodes>: ViewModifier {
  let viewModel: ViewModel
  let episode: ViewModel.EpisodeType

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading) {
        Button(
          action: { viewModel.queueEpisodeOnTop(episode) },
          label: {
            AppLabel.queueAtTop.image
          }
        )
        .tint(.blue)

        Button(
          action: { viewModel.queueEpisodeAtBottom(episode) },
          label: {
            AppLabel.queueAtBottom.image
          }
        )
        .tint(.purple)
      }

      .swipeActions(edge: .trailing) {
        Button(
          action: { viewModel.playEpisode(episode) },
          label: {
            AppLabel.playEpisode.image
          }
        )
        .tint(.green)
      }
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
