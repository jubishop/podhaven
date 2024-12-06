// Copyright Justin Bishop, 2024

import GRDB
import NukeUI
import SwiftUI

struct PodcastsView: View {
  @State private var viewModel = PodcastsViewModel()
  private let numberOfColumns = 3

  init(repository: PodcastRepository = .shared) {
    _viewModel = State(initialValue: PodcastsViewModel(repository: repository))
  }

  var body: some View {
    NavigationStack {
      ThumbnailGrid(podcasts: $viewModel.podcasts)
    }
    .task {
      await viewModel.observePodcasts()
    }
  }
}

#Preview {
  Preview { PodcastsView() }
}
