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
    }
    .navigationTitle(viewModel.podcast.title)
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
        try! Podcast.filter(Column("title") == "Hard Fork").fetchOne(db)!
      }
    }

    var body: some View {
      SeriesView(podcast: podcast)
    }
  }

  return Preview { NavigationStack { SeriesViewPreview() } }
}
