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
          Label("Play Episode", systemImage: "play.fill")
        }

        Button(action: { viewModel.queueEpisodeOnTop(episode) }) {
          Label("Queue at Top", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button(action: { viewModel.queueEpisodeAtBottom(episode) }) {
          Label("Queue at Bottom", systemImage: "text.line.last.and.arrowtriangle.forward")
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
