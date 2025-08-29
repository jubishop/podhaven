// Copyright Justin Bishop, 2025

import SwiftUI

/// This prevents issues where parent views interfere with child view updates
/// by adding a layer of isolation between the parent and the EpisodeDetailView.
struct EpisodeDetailWrapperView: View {
  let podcastEpisode: PodcastEpisode

  var body: some View {
    EpisodeDetailView(viewModel: EpisodeDetailViewModel(episode: podcastEpisode))
  }
}
