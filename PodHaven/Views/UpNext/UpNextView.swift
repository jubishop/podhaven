// Copyright Justin Bishop, 2024

import SwiftUI

struct UpNextView: View {
  @Environment(\.editMode) private var editMode
  @State private var isEditing: Bool = false

  @State private var navigation = Navigation.shared
  @State private var viewModel = UpNextViewModel()

  // TODO: Move this to the viewModel
  @State private var isSelected = BindableDictionary<PodcastEpisode, Bool>(
    defaultValue: false
  )

  var body: some View {
    NavigationStack(path: $navigation.upNextPath) {
      List {
        // TODO: Swipe right to go to top of queue
        ForEach(viewModel.podcastEpisodes) { podcastEpisode in
          UpNextListView(
            isSelected: $isSelected[podcastEpisode],
            podcastEpisode: podcastEpisode
          )
        }
        .onMove(perform: viewModel.moveItem)
        .onDelete(perform: viewModel.deleteItems)
      }
      .animation(.default, value: Array(viewModel.podcastEpisodes))
      .navigationTitle("Up Next")
      .navigationDestination(for: PodcastEpisode.self) { podcastEpisode in
        EpisodeView(podcastEpisode: podcastEpisode)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          EditButton { isEditing in
            self.isEditing = isEditing
          }
        }
        if isEditing {
          ToolbarItem(placement: .topBarLeading) {
            Button(
              action: {
                // TODO: Move this to the viewModel
                let selectedItems = isSelected.keys.filter { isSelected[$0] }
                Task {
                  for selectedItem in selectedItems {
                    try await Repo.shared.dequeue(selectedItem.episode.id)
                  }
                }
              },
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
