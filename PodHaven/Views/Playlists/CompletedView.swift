// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct CompletedView: View {
  @Environment(Alert.self) var alert

  @State private var navigation = Container.shared.navigation()
  @State private var viewModel = CompletedViewModel()

  var body: some View {
    List {
      ForEach(viewModel.podcastEpisodes) { podcastEpisode in
        CompletedListView(
          viewModel: CompletedListViewModel(
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
      }
    }
    .navigationTitle("Completed Episodes")
    .environment(\.editMode, $viewModel.editMode)
    .animation(.default, value: viewModel.podcastEpisodes.elements)
    .toolbar {
      if viewModel.isEditing {
        ToolbarItem(placement: .topBarTrailing) {
          SelectableListMenu(list: viewModel.episodeList)
        }
      }

      ToolbarItem(placement: (viewModel.isEditing ? .topBarLeading : .topBarTrailing)) {
        EditButton()
          .environment(\.editMode, $viewModel.editMode)
      }
    }
    .toolbarRole(.editor)
    .task { await viewModel.execute() }
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    CompletedView()
  }
  .preview()
  .task { try? await PreviewHelpers.populateCompletedPodcastEpisodes() }
}
#endif

