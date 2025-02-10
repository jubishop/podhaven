// Copyright Justin Bishop, 2025

import SwiftUI

struct EpisodeListView: View {
  private let viewModel: EpisodeListViewModel

  init(viewModel: EpisodeListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    Text(viewModel.episode.toString)
  }
}

#Preview {
  @Previewable @State var episode: Episode?

  List {
    if let episode = episode {
      EpisodeListView(
        viewModel: EpisodeListViewModel(
          isSelected: .constant(false),
          episode: episode,
          isEditing: false
        )
      )
    } else {
      Text("No episodes in DB")
    }
  }
  .preview()
  .task {
    episode = try? await PreviewHelpers.loadEpisode()
  }
}
