// Copyright Justin Bishop, 2024

import SwiftUI

struct UpNextListView: View {
  let podcastEpisode: PodcastEpisode
  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }

  var body: some View {
    NavigationLink(
      value: podcastEpisode,
      label: {
        Text(episode.toString)
      }
    )
  }
}

#Preview {
  struct UpNextListViewPreview: View {
    @State var podcastEpisode: PodcastEpisode?

    var body: some View {
      Group {
        if let podcastEpisode = self.podcastEpisode {
          UpNextListView(podcastEpisode: podcastEpisode)
        } else {
          Text("No episodes in DB")
        }
      }
      .task {
        self.podcastEpisode = try? await Helpers.loadPodcastEpisode()
      }
    }
  }

  return Preview { NavigationStack { UpNextListViewPreview() } }
}

