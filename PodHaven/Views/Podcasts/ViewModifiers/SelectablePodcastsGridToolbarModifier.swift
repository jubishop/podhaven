// Copyright Justin Bishop, 2025

import SwiftUI

struct SelectablePodcastsGridToolbarModifier: ViewModifier {
  @State private var viewModel: SelectablePodcastsGridViewModel

  init(viewModel: SelectablePodcastsGridViewModel) {
    self.viewModel = viewModel
  }

  func body(content: Content) -> some View {
    content
      .toolbar {
        if viewModel.isSelecting {
          ToolbarItem(placement: .primaryAction) {
            SelectableListMenu(list: viewModel.podcastList)
          }

          if viewModel.podcastList.anySelected {
            ToolbarItem(placement: .primaryAction) {
              Menu(
                content: {
                  if viewModel.anySelectedSaved {
                    Button("Delete") {
                      viewModel.deleteSelectedPodcasts()
                    }
                  }

                  if viewModel.anySelectedUnsubscribed {
                    Button("Subscribe") {
                      viewModel.subscribeSelectedPodcasts()
                    }
                  }

                  if viewModel.anySelectedSubscribed {
                    Button("Unsubscribe") {
                      viewModel.unsubscribeSelectedPodcasts()
                    }
                  }
                },
                label: {
                  AppIcon.moreActions.image
                }
              )
            }
          }

          ToolbarItem(placement: .cancellationAction) {
            Button(AppIcon.editFinished.text) {
              viewModel.isSelecting = false
            }
          }
        } else {
          ToolbarItem(placement: .primaryAction) {
            Menu(
              content: {
                ForEach(viewModel.allSortMethods, id: \.self) { sortMethod in
                  sortMethod.appIcon
                    .labelButton {
                      viewModel.currentSortMethod = sortMethod
                    }
                    .disabled(viewModel.currentSortMethod == sortMethod)
                }
              },
              label: { viewModel.currentSortMethod.appIcon.image }
            )
          }

          ToolbarItem(placement: .primaryAction) {
            Button(AppIcon.editItems.text) {
              viewModel.isSelecting = true
            }
          }
        }
      }
      .toolbarRole(.editor)
  }
}

extension View {
  func selectablePodcastsGridToolbar(
    viewModel: SelectablePodcastsGridViewModel
  ) -> some View {
    self.modifier(SelectablePodcastsGridToolbarModifier(viewModel: viewModel))
  }
}
