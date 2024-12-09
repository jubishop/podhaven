// Copyright Justin Bishop, 2024

import SwiftUI

struct EpisodeListView: View {
  let episode: Episode

  var body: some View {
    NavigationLink(
      value: episode,
      label: {
        Text(episode.title ?? "No Title")
      }
    )
  }
}

// TODO
//#Preview {
//    EpisodeListView()
//}
