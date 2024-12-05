// Copyright Justin Bishop, 2024

import SwiftUI

struct PodcastsView: View {
  @State private var viewModel = PodcastsViewModel()

  init(repository: PodcastRepository = .shared) {
    _viewModel = State(initialValue: PodcastsViewModel(repository: repository))
  }

  var body: some View {
    List(viewModel.podcasts) { podcast in
      Text(podcast.title)
    }.task {
      await viewModel.observePodcasts()
    }
  }
}

#Preview {
  Preview { PodcastsView(repository: .empty()) }
}
