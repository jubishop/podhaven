// Copyright Justin Bishop, 2024

import SwiftUI

struct UpNextView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = UpNextViewModel()
  @State private var isEditing: Bool = false

  var body: some View {
    NavigationStack(path: $navigation.upNextPath) {
      List {
        ForEach(viewModel.podcastEpisodes) { podcastEpisode in
          UpNextListView(
            isSelected: $viewModel.isSelected[podcastEpisode],
            podcastEpisode: podcastEpisode
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
        }
        .onMove(perform: viewModel.moveItem)
        .onDelete(perform: viewModel.deleteOffsets)
      }
      .animation(.default, value: Array(viewModel.podcastEpisodes))
      .navigationTitle("Up Next")
      .navigationDestination(for: PodcastEpisode.self) { podcastEpisode in
        EpisodeView(podcastEpisode: podcastEpisode)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          EditButton { isEditing in self.isEditing = isEditing }
        }
        if isEditing {
          ToolbarItem(placement: .topBarLeading) {
            Button(
              action: viewModel.deleteSelected,
              label: { Text("Delete Selected") }
            )
          }
        }
      }
      .task {
        await viewModel.observeQueuedEpisodes()
      }
    }
  }
}

#Preview {
  struct UpNextViewPreview: View {

    var body: some View {
      UpNextView()
        .task { try? await Helpers.populateQueue() }
    }
  }

  return Preview { UpNextViewPreview() }
}
