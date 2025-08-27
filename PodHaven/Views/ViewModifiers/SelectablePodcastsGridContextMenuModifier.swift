// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SelectablePodcastsGridContextMenuModifier: ViewModifier {
  let viewModel: SelectablePodcastsGridViewModel
  let podcast: Podcast

  func body(content: Content) -> some View {
    content
      .contextMenu {
        Button(
          action: { viewModel.queueLatestEpisodeToTop(podcast.id) },
          label: {
            Label(
              "Queue Latest To Top",
              systemImage: AppLabel.queueLatestToTop.systemImageName
            )
          }
        )

        Button(
          action: { viewModel.queueLatestEpisodeToBottom(podcast.id) },
          label: {
            Label(
              "Queue Latest To Bottom",
              systemImage: AppLabel.queueLatestToBottom.systemImageName
            )
          }
        )

        Button(
          action: { viewModel.deletePodcast(podcast.id) },
          label: { AppLabel.delete.label }
        )

        if podcast.subscribed {
          Button(
            action: { viewModel.unsubscribePodcast(podcast.id) },
            label: { AppLabel.unsubscribe.label }
          )
        } else {
          Button(
            action: { viewModel.subscribePodcast(podcast.id) },
            label: { AppLabel.subscribe.label }
          )
        }
      }
  }
}

extension View {
  func selectablePodcastsGridContextMenu(
    viewModel: SelectablePodcastsGridViewModel,
    podcast: Podcast
  ) -> some View {
    self.modifier(
      SelectablePodcastsGridContextMenuModifier(viewModel: viewModel, podcast: podcast)
    )
  }
}
