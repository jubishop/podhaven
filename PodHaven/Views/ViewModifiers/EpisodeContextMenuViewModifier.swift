// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct EpisodeContextMenuViewModifier<
  ViewModel: ManagingEpisodes,
  AdditionalContent: View
>: ViewModifier {
  let viewModel: ViewModel
  let episode: any EpisodeDisplayable
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
  func episodeContextMenu<ViewModel: ManagingEpisodes, AdditionalContent: View>(
    viewModel: ViewModel,
    episode: any EpisodeDisplayable,
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
