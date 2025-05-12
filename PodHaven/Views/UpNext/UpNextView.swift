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
              isSelected: $viewModel.episodeList.isSelected[podcastEpisode],
              podcastEpisode: podcastEpisode,
              editMode: viewModel.editMode
            )
          )
          .swipeActions(edge: .leading) {
            Button(
              action: { viewModel.playItem(podcastEpisode) },
              label: {
                Label("Play Now", systemImage: "play.fill")
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
    }
    .task { await viewModel.execute() }
  }
}

#if DEBUG
#Preview {
  UpNextView()
    .preview()
    .task { try? await PreviewHelpers.populateQueue() }
}
#endif
