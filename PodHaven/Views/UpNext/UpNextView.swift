// Copyright Justin Bishop, 2024

import SwiftUI

struct UpNextView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = UpNextViewModel()

  var body: some View {
    NavigationStack(path: $navigation.upNextPath) {
      List {
        ForEach(viewModel.podcastEpisodes) { podcastEpisode in
          UpNextListView(
            viewModel: UpNextListViewModel(
              isSelected: $viewModel.isSelected[podcastEpisode],
              podcastEpisode: podcastEpisode,
              editMode: viewModel.editMode
            )
          )
          .swipeActions(edge: .leading) {
            Button(
              action: { viewModel.moveToTop(podcastEpisode) },
              label: {
                Label("Move to Top", systemImage: "arrow.up")
              }
            )
            .tint(.green)
          }
          .swipeActions(edge: .trailing) {
            Button(
              action: { viewModel.deleteItem(podcastEpisode) },
              label: {
                Label("Delete", systemImage: "trash")
              }
            )
            .tint(.red)
          }
        }
        .onMove(perform: viewModel.moveItem)
      }
      .environment(\.editMode, $viewModel.editMode)
      .animation(.default, value: Array(viewModel.podcastEpisodes))
      .navigationTitle("Up Next")
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          if viewModel.isEditing {
            if viewModel.anySelected {
              Button(
                action: viewModel.deleteSelected,
                label: { Text("Delete Selected") }
              )
              Button(
                action: viewModel.unselectAll,
                label: { Text("Unselect All") }
              )
            } else {
              Button(
                action: { viewModel.deleteAll() },
                label: { Text("Delete All") }
              )
            }
          }
          EditButton()
            .environment(\.editMode, $viewModel.editMode)
        }
      }
      .toolbarRole(.navigationStack)
      .task { await viewModel.observeQueuedEpisodes() }
    }
  }
}

#Preview {
  Preview {
    UpNextView()
      .task { try? await Helpers.populateQueue() }
  }
}
