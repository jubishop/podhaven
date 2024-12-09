// Copyright Justin Bishop, 2024

import GRDB
import SwiftUI

struct SeriesView: View {
  @State private var viewModel: SeriesViewModel

  init(podcast: Podcast) {
    _viewModel = State(initialValue: SeriesViewModel(podcast: podcast))
  }

  var body: some View {
    VStack {
      if let description = viewModel.podcast.description {
        HTMLText(description).padding()
      }
      List(Array(viewModel.episodes)) { episode in
        EpisodeListView(episode: episode)
      }
    }
    .navigationTitle(viewModel.podcast.title)
    .navigationDestination(for: Episode.self) { episode in
      EpisodeView(episode: episode)
    }
    .task {
      await viewModel.observePodcasts()
    }
  }
}

#Preview {
  struct SeriesViewPreview: View {
    let podcast: Podcast
    init() {
      self.podcast = try! PodcastRepository.shared.db.read { db in
        try! Podcast.fetchOne(db)!
      }
    }

    var body: some View {
      SeriesView(podcast: podcast)
    }
  }

  return Preview { NavigationStack { SeriesViewPreview() } }
}
