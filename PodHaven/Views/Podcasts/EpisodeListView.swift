// Copyright Justin Bishop, 2025

import SwiftUI

struct EpisodeListView: View {
  private let podcastEpisode: PodcastEpisode
  private var podcast: Podcast { podcastEpisode.podcast }
  private var episode: Episode { podcastEpisode.episode }

  init(podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode
  }

  var body: some View {
    Text(episode.toString)
  }
}

#Preview {
  @Previewable @State var podcastEpisode: PodcastEpisode?

  List {
    if let podcastEpisode = podcastEpisode {
      EpisodeListView(podcastEpisode: podcastEpisode)
    } else {
      Text("No episodes in DB")
    }
  }
  .preview()
  .task {
    podcastEpisode = try? await PreviewHelpers.loadPodcastEpisode()
  }
}
