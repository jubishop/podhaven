// Copyright Justin Bishop, 2024

import SwiftUI

struct UpNextView: View {
  @State private var navigation = Navigation.shared
  @State private var viewModel = UpNextViewModel()

  var body: some View {
    NavigationStack(path: $navigation.upNextPath) {
      List {
        // TODO: Swipe right to go to top of queue
        ForEach(viewModel.podcastEpisodes) { podcastEpisode in
          UpNextListView(podcastEpisode: podcastEpisode)
        }
        .onMove(perform: viewModel.moveItem)
        .onDelete(perform: viewModel.deleteItems)
      }
      .navigationTitle("Up Next")
      .navigationDestination(for: PodcastEpisode.self) { podcastEpisode in
        EpisodeView(podcastEpisode: podcastEpisode)
      }
      .toolbar {
        EditButton()
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
