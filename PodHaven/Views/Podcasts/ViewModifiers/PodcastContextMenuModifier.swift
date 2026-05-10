// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

struct PodcastContextMenuModifier<ViewModel: ManagingPodcasts>: ViewModifier {
  @DynamicInjected(\.sharedState) private var sharedState

  let viewModel: ViewModel
  let podcast: ViewModel.PodcastType
  let tagIDs: Set<Tag.ID>?

  func body(content: Content) -> some View {
    content
      .contextMenu {
        AppIcon.queueAtTop.labelButton {
          viewModel.queueLatestEpisodeToTop(podcast)
        }

        AppIcon.queueAtBottom.labelButton {
          viewModel.queueLatestEpisodeToBottom(podcast)
        }

        if podcast.isSaved {
          AppIcon.delete.labelButton {
            viewModel.deletePodcast(podcast)
          }
        }

        if podcast.subscribed {
          AppIcon.unsubscribe.labelButton {
            viewModel.unsubscribePodcast(podcast)
          }
        } else {
          AppIcon.subscribe.labelButton {
            viewModel.subscribePodcast(podcast)
          }
        }

        if let tagIDs, podcast.isSaved {
          tagMenu(tagIDs: tagIDs)
        }
      }
  }

  // Filtered Add/Remove submenus. Hidden whole-cloth when both filtered
  // lists are empty so we never offer a submenu that would no-op.
  @ViewBuilder
  private func tagMenu(tagIDs: Set<Tag.ID>) -> some View {
    let allTags = sharedState.tags
    let addable = allTags.filter { !tagIDs.contains($0.id) }
    let removable = allTags.filter { tagIDs.contains($0.id) }

    if !addable.isEmpty || !removable.isEmpty {
      Menu {
        if !addable.isEmpty {
          Menu {
            ForEach(addable) { tag in
              Button(tag.name) {
                viewModel.addTag(tag.id, to: podcast)
              }
            }
          } label: {
            AppIcon.addTag.label("Add Tag")
          }
        }

        if !removable.isEmpty {
          Menu {
            ForEach(removable) { tag in
              Button(tag.name) {
                viewModel.removeTag(tag.id, from: podcast)
              }
            }
          } label: {
            AppIcon.removeTag.label("Remove Tag")
          }
        }
      } label: {
        AppIcon.tag.label("Tag")
      }
    }
  }
}

extension View {
  func podcastContextMenu<ViewModel: ManagingPodcasts>(
    viewModel: ViewModel,
    podcast: ViewModel.PodcastType,
    tagIDs: Set<Tag.ID>? = nil
  ) -> some View {
    self.modifier(
      PodcastContextMenuModifier(
        viewModel: viewModel,
        podcast: podcast,
        tagIDs: tagIDs
      )
    )
  }
}
