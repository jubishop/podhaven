// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct UpNextView: View {
  @DynamicInjected(\.alert) private var alert
  @InjectedObservable(\.navigation) private var navigation

  @State private var viewModel = UpNextViewModel()

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.upNext) {
      List {
        ForEach(viewModel.podcastEpisodes) { podcastEpisode in
          NavigationLink(
            value: Navigation.UpNext.Destination.episode(podcastEpisode),
            label: {
              UpNextListView(
                viewModel: UpNextListViewModel(
                  isSelected: $viewModel.episodeList.isSelected[podcastEpisode],
                  podcastEpisode: podcastEpisode,
                  editMode: viewModel.editMode
                )
              )
            }
          )
          .upNextSwipeActions(viewModel: viewModel, podcastEpisode: podcastEpisode)
          .upNextContextMenu(viewModel: viewModel, podcastEpisode: podcastEpisode)
        }
        .onMove(perform: viewModel.moveItem)
      }
      .refreshable { viewModel.refreshQueue() }
      .navigationTitle("Up Next")
      .environment(\.editMode, $viewModel.editMode)
      .animation(.default, value: viewModel.podcastEpisodes)
      .toolbar {
        if viewModel.isEditing {
          ToolbarItem(placement: .topBarTrailing) {
            SelectableListMenu(list: viewModel.episodeList)
          }

          if viewModel.episodeList.anySelected {
            ToolbarItem(placement: .topBarTrailing) {
              Menu(
                content: {
                  Button("Delete Selected") {
                    viewModel.deleteSelected()
                  }
                },
                label: {
                  Image(systemName: "minus.circle")
                }
              )
            }
          }
        } else {
          ToolbarItem(placement: .topBarLeading) {
            Text(viewModel.totalQueueDuration.shortDescription)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          ToolbarItem(placement: .topBarTrailing) {
            Menu("Sort") {
              ForEach(UpNextViewModel.SortMethod.allCases, id: \.self) { method in
                Button(method.rawValue) {
                  viewModel.sort(by: method)
                }
              }
            }
          }
        }

        ToolbarItem(placement: (viewModel.isEditing ? .topBarLeading : .topBarTrailing)) {
          EditButton()
            .environment(\.editMode, $viewModel.editMode)
        }
      }
      .toolbarRole(.editor)
      .navigationDestination(
        for: Navigation.UpNext.Destination.self,
        destination: navigation.upNext.navigationDestination
      )
    }
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  UpNextView()
    .preview()
    .task { try? await PreviewHelpers.populateQueue() }
}
#endif
