// Copyright Justin Bishop, 2024

import SwiftUI

struct EpisodeListView: View {
  let episode: Episode

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
    let episode: Episode
    init() {
      self.episode = try! Repo.shared.db.read { db in
        try! Episode.fetchOne(db)!
      }
    }

    var body: some View {
      EpisodeListView(episode: episode)
    }
  }

  return Preview { NavigationStack { EpisodeListViewPreview() } }
}
