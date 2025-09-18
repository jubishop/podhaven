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
        Button(
          action: { viewModel.playEpisode(episode) },
          label: { AppLabel.playEpisode.label }
        )

        Button(
          action: { viewModel.queueEpisodeOnTop(episode) },
          label: { AppLabel.queueAtTop.label }
        )

        Button(
          action: { viewModel.queueEpisodeAtBottom(episode) },
          label: { AppLabel.queueAtBottom.label }
        )

        if episode.caching {
          Button(
            action: { viewModel.uncacheEpisode(episode) },
            label: { AppLabel.cancelEpisodeDownload.label }
          )
        } else if episode.cached {
          Button(
            action: { viewModel.uncacheEpisode(episode) },
            label: { AppLabel.uncacheEpisode.label }
          )

        } else {
          Button(
            action: { viewModel.cacheEpisode(episode) },
            label: { AppLabel.cacheEpisode.label }
          )
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
