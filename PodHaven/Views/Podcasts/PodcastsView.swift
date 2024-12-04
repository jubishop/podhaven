// Copyright Justin Bishop, 2024

import SwiftUI

struct PodcastsView: View {
  @State private var viewModel = PodcastsViewModel()

  init(repository: PodcastRepository = .shared) {
    _viewModel = State(initialValue: PodcastsViewModel(repository: repository))
    viewModel.observePodcasts()
  }

  var body: some View {
    List(viewModel.podcasts) { podcast in
      Text(podcast.title)
    }
  }
}

#Preview {
  Preview { PodcastsView(repository: .empty()) }
}
