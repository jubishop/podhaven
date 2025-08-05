// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct UpNextView: View {
  @DynamicInjected(\.alert) private var alert
  @InjectedObservable(\.navigation) private var navigation

  @State private var viewModel = UpNextViewModel()

  var body: some View {
    NavigationStack {
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
          .swipeActions(edge: .leading) {
            Button(
              action: { viewModel.playItem(podcastEpisode) },
              label: {
                Image(systemName: "play.fill")
              }
            )
            .tint(.green)
          }
          .swipeActions(edge: .trailing) {
            Button(
              role: .destructive,
              action: { viewModel.deleteItem(podcastEpisode) },
              label: {
                Image(systemName: "trash")
              }
            )
            .tint(.red)
          }
        }
        .onMove(perform: viewModel.moveItem)
      }
      .navigationTitle("Up Next")
      .environment(\.editMode, $viewModel.editMode)
      .animation(.default, value: viewModel.podcastEpisodes)
      .toolbar {
        if viewModel.isEditing {
          ToolbarItem(placement: .topBarTrailing) {
            SelectableListMenu(list: viewModel.episodeList)
          }
        }

        if viewModel.isEditing, viewModel.episodeList.anySelected {
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
