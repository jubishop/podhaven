// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeQueueableContextMenuViewModifier<
  ViewModel: EpisodeQueueable,
  AdditionalContent: View
>: ViewModifier {
  let viewModel: ViewModel
  let episode: ViewModel.EpisodeType
  @ViewBuilder let additionalContent: () -> AdditionalContent

  func body(content: Content) -> some View {
    content
      .contextMenu {
        Button(action: { viewModel.playEpisode(episode) }) {
          AppLabel.playEpisode.label
        }

        Button(action: { viewModel.queueEpisodeOnTop(episode) }) {
          AppLabel.queueAtTop.label
        }

        Button(action: { viewModel.queueEpisodeAtBottom(episode) }) {
          AppLabel.queueAtBottom.label
        }
        
        Button(action: { viewModel.cacheEpisode(episode) }) {
          AppLabel.cacheEpisode.label
        }

        additionalContent()
      }
  }
}

extension View {
  func episodeQueueableContextMenu<ViewModel: EpisodeQueueable, AdditionalContent: View>(
    viewModel: ViewModel,
    episode: ViewModel.EpisodeType,
    @ViewBuilder additionalContent: @escaping () -> AdditionalContent = { EmptyView() }
  ) -> some View {
    self.modifier(
      EpisodeQueueableContextMenuViewModifier(
        viewModel: viewModel,
        episode: episode,
        additionalContent: additionalContent
      )
    )
  }
}
