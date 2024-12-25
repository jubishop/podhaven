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
  struct EpisodeListViewPreview: View {
    @State var podcastEpisode: PodcastEpisode?

    var body: some View {
      Group {
        if let podcastEpisode = self.podcastEpisode {
          EpisodeListView(podcastEpisode: podcastEpisode)
        } else {
          Text("No episodes in DB")
        }
      }
      .task {
        self.podcastEpisode = try? await Helpers.loadPodcastEpisode()
      }
    }
  }

  return Preview { NavigationStack { EpisodeListViewPreview() } }
}
