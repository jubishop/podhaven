// Copyright Justin Bishop, 2024

import SwiftUI

struct EpisodeView: View {
  @State private var viewModel: EpisodeViewModel

  init(episode: Episode) {
    _viewModel = State(initialValue: EpisodeViewModel(episode: episode))
  }

  var body: some View {
    Text(viewModel.episode.title ?? "No Title")
      .task {
        await viewModel.observeEpisode()
      }
  }
}

//#Preview {
//    EpisodeView()
//}
