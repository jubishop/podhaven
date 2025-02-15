// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct UpNextView: View {
  @Environment(Alert.self) var alert

  @State private var navigation = Container.shared.navigation()
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
              role: .destructive,
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
      .navigationTitle("Up Next")
      .environment(\.editMode, $viewModel.editMode)
      .animation(.default, value: Array(viewModel.podcastEpisodes))
      .toolbar {
        if viewModel.isEditing {
          if viewModel.anySelected {
            ToolbarItemGroup(placement: .topBarTrailing) {
              Button("Delete Selected") {
                viewModel.deleteSelected()
              }

              Button("Unselect All") {
                viewModel.unselectAll()
              }
            }
          } else {
            ToolbarItem(placement: .topBarTrailing) {
              Button("Delete All") {
                viewModel.deleteAll()
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
    }
    .task { await viewModel.execute() }
  }
}

#Preview {
  UpNextView()
    .preview()
    .task { try? await PreviewHelpers.populateQueue() }
}
