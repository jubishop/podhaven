// Copyright Justin Bishop, 2024

import SwiftUI

struct EpisodeListView: View {
  let podcastEpisode: PodcastEpisode
  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }

  var body: some View {
    NavigationLink(
      value: episode,
      label: {
        Text(episode.toString)
      }
    )
  }
}

#Preview {
  @Previewable @State var podcastEpisode: PodcastEpisode?

  Preview {
    NavigationStack {
      if let podcastEpisode = podcastEpisode {
        EpisodeListView(podcastEpisode: podcastEpisode)
      } else {
        Text("No episodes in DB")
      }
    }
  }
  .task {
    podcastEpisode = try? await PreviewHelpers.loadPodcastEpisode()
  }
}
